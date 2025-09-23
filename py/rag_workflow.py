import os
import json
import platform
import hashlib
from pathlib import Path
from typing import TypedDict, List

from langchain_community.vectorstores import Chroma
from langchain.prompts import ChatPromptTemplate
from langchain_google_genai import GoogleGenerativeAIEmbeddings, ChatGoogleGenerativeAI
from langchain.schema.output_parser import StrOutputParser
from langchain.schema.document import Document
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langgraph.graph import StateGraph, END

from gemini_ai import EMBEDDING_MODEL, DEFAULT_GEMINI_MODEL


def _get_db_path() -> str:
    """실행 중인 OS를 감지하여 ChromaDB 저장소의 동적 경로를 반환합니다."""
    home_dir = Path.home()
    system = platform.system()
    if system == "Darwin":  # macOS
        notes_dir = home_dir / "Memordo_Notes"
    else:  # Windows, Linux 등
        notes_dir = home_dir / "Documents" / "Memordo_Notes"
    
    db_path = notes_dir / "chroma_db"
    os.makedirs(db_path, exist_ok=True)
    return str(db_path)

def _get_content_hash(content: str) -> str:
    """주어진 내용의 SHA-256 해시를 계산합니다."""
    return hashlib.sha256(content.encode('utf-8')).hexdigest()

class GraphState(TypedDict):
    # --- [수정] --- 원본 질문을 저장할 필드 추가
    original_question: str
    question: str
    notes: List[dict]
    edges: List[dict]
    documents: List[Document]
    vectorstore: Chroma
    connected_nodes: set
    isolated_nodes: set
    top_docs: List[Document]
    expanded_docs: List[Document]
    final_context: str
    answer: str
    sources: List[str]

PROMPT_TEMPLATES = {
    "expand_note": ChatPromptTemplate.from_template(
        """다음 메모는 내용이 너무 짧아 문맥이 부족합니다.
        메모의 핵심 의미를 유지하면서, 이 메모가 어떤 상황에서 작성되었을지 추론하여 내용을 보강해주세요.
        보강된 내용만 간결하게 답변해주세요.
        
        --- 원본 메모 ---
        {original_content}
        """
    ),
    # --- [수정] --- '질문 확장' 대신 '가상 문서 생성(HyDE)' 프롬프트로 변경
    "generate_hyde": ChatPromptTemplate.from_template(
        """당신은 주어진 질문에 대해 가장 이상적인 답변을 생성하는 AI입니다.
        이 답변은 실제 문서를 찾는 데 사용될 검색어 역할을 합니다.
        질문의 핵심 의도를 파악하여, 그에 대한 완벽한 답변을 상세하게 작성해주세요.

        --- 원본 질문 ---
        {question}

        --- 이상적인 답변 ---
        """
    ),
    "generate_answer": ChatPromptTemplate.from_template(
        """당신은 사용자의 노트를 기반으로 질문에 답변하는 AI 비서 'Memordo'입니다.
        아래에 제공되는 "노트 내용"을 참고하여 사용자의 "질문"에 대해 상세하고 친절하게 답변해주세요.
        답변은 반드시 "노트 내용"에 근거해야 하며, 내용에 없는 정보는 답변하지 마세요.
        어떤 노트를 참고했는지 명시해주면 좋습니다.

        --- 노트 내용 ---
        {context}
        ---

        질문: {question}

        답변:"""
    )
}

def expand_short_notes(state: GraphState) -> dict:
    print("--- (Node 0) 짧은 메모 보강 시작 ---")
    notes = state['notes']
    MIN_CHARS_FOR_EXPANSION = 100
    updated_notes = []
    llm = ChatGoogleGenerativeAI(model=DEFAULT_GEMINI_MODEL, temperature=0.5)
    prompt = PROMPT_TEMPLATES["expand_note"]
    chain = prompt | llm | StrOutputParser()
    for note in notes:
        if len(note['content']) < MIN_CHARS_FOR_EXPANSION:
            print(f"     - '{note['fileName']}' 보강 필요 (현재 {len(note['content'])}자)")
            expanded_content = chain.invoke({"original_content": note['content']})
            note['retrieval_content'] = expanded_content
            print(f"     - 보강 완료: {expanded_content[:50]}...")
        else:
            note['retrieval_content'] = note['content']
        updated_notes.append(note)
    return {"notes": updated_notes}

# --- [수정] --- 함수 이름을 명확하게 변경하고, 가상 문서를 생성하도록 로직 수정
def generate_hypothetical_document(state: GraphState) -> dict:
    """HyDE: 검색 성능 향상을 위해 질문에 대한 가상의 답변 문서를 생성합니다."""
    print("--- (Node 1) 가상 문서 생성 (HyDE) 시작 ---")
    original_question = state['original_question']
    
    llm = ChatGoogleGenerativeAI(model=DEFAULT_GEMINI_MODEL, temperature=0)
    prompt = PROMPT_TEMPLATES["generate_hyde"]
    chain = prompt | llm | StrOutputParser()
    
    hypothetical_document = chain.invoke({"question": original_question})
    
    print(f"     - 원본 질문: \"{original_question}\"")
    print(f"     - 생성된 가상 문서: \"{hypothetical_document[:100]}...\"")
    
    # 'question' 필드를 가상 문서로 덮어써서 다음 검색 단계에서 사용하도록 함
    return {"question": hypothetical_document}

def prepare_retrieval(state: GraphState) -> dict:
    """[REFACTORED] 해시 비교를 통해 노트의 추가, 수정, 삭제를 감지하고 DB를 동기화합니다."""
    print("--- (Node 2) 검색 준비, 벡터 저장소 동기화 ---")
    notes = state['notes']
    edges = state['edges']
    db_path = _get_db_path()

    embedding_function = GoogleGenerativeAIEmbeddings(model=EMBEDDING_MODEL, task_type="retrieval_document")
    vectorstore = Chroma(persist_directory=db_path, embedding_function=embedding_function)

    local_notes_state = {note['fileName']: _get_content_hash(note['content']) for note in notes}
    
    db_docs = vectorstore.get(include=["metadatas"])
    db_notes_state = {}
    db_chunks_map = {}
    for i, metadata in enumerate(db_docs['metadatas']):
        source = metadata.get('source')
        content_hash = metadata.get('content_hash')
        if source and content_hash:
            if source not in db_notes_state:
                db_notes_state[source] = content_hash
            if source not in db_chunks_map:
                db_chunks_map[source] = []
            db_chunks_map[source].append(db_docs['ids'][i])

    local_files = set(local_notes_state.keys())
    db_files = set(db_notes_state.keys())
    
    files_to_add = local_files - db_files
    files_to_delete = db_files - local_files
    files_to_check = local_files.intersection(db_files)
    
    files_to_update = {
        f for f in files_to_check if local_notes_state[f] != db_notes_state[f]
    }
    
    ids_to_delete = []
    files_for_resync = files_to_delete.union(files_to_update)
    if files_for_resync:
        for file_name in files_for_resync:
            ids_to_delete.extend(db_chunks_map.get(file_name, []))
        if ids_to_delete:
            print(f"     - 삭제/수정된 {len(files_for_resync)}개 노트의 기존 청크 {len(ids_to_delete)}개를 삭제합니다.")
            vectorstore.delete(ids=ids_to_delete)

    notes_to_process = files_to_add.union(files_to_update)
    if notes_to_process:
        print(f"     - 신규/수정된 {len(notes_to_process)}개 노트를 처리합니다.")
        notes_to_add_data = [n for n in notes if n['fileName'] in notes_to_process]
        
        text_splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)
        
        all_new_chunks = []
        for note in notes_to_add_data:
            content_hash = local_notes_state[note['fileName']]
            chunks = text_splitter.split_text(note['retrieval_content'])
            for i, chunk_text in enumerate(chunks):
                chunk_doc = Document(
                    page_content=chunk_text,
                    metadata={
                        'source': note['fileName'],
                        'original_content': note['content'],
                        'content_hash': content_hash
                    }
                )
                chunk_id = f"{note['fileName']}_{i}"
                all_new_chunks.append((chunk_id, chunk_doc))

        if all_new_chunks:
            ids_to_add = [c[0] for c in all_new_chunks]
            docs_to_add = [c[1] for c in all_new_chunks]
            
            vectorstore.add_documents(documents=docs_to_add, ids=ids_to_add)
            print(f"     - 총 {len(all_new_chunks)}개의 신규 청크를 DB에 추가했습니다.")

    if not files_to_add and not files_for_resync:
        print("     - DB와 동기화 완료. 변경 사항 없음.")

    documents = [Document(page_content=note['content'], metadata={'source': note['fileName']}) for note in notes]
    connected_nodes = {edge['from'] for edge in edges} | {edge['to'] for edge in edges}
    isolated_nodes = set(local_notes_state.keys()) - connected_nodes
    
    print(f"     - 동기화 후 노드: {len(local_notes_state)}개 (연결: {len(connected_nodes)}, 고립: {len(isolated_nodes)})")
    
    return {"documents": documents, "vectorstore": vectorstore, "connected_nodes": connected_nodes, "isolated_nodes": isolated_nodes}

def first_pass_retrieval(state: GraphState) -> dict:
    print("--- (Node 3) 1차 검색 수행 ---")
    question = state['question']
    db_path = _get_db_path()

    query_embedding_function = GoogleGenerativeAIEmbeddings(model=EMBEDDING_MODEL, task_type="retrieval_query")
    vectorstore = Chroma(
        persist_directory=db_path,
        embedding_function=query_embedding_function
    )

    if vectorstore._collection.count() == 0:
        print("     - 벡터 저장소가 비어있어 검색을 건너뜁니다.")
        return {"top_docs": []}

    retriever = vectorstore.as_retriever(search_kwargs={"k": 10})
    top_docs = retriever.invoke(question)
    
    print(f"     - 1차 검색 결과 (상위 {len(top_docs)}개): {[doc.metadata['source'] for doc in top_docs]}")
    return {"top_docs": top_docs}

def analyze_and_branch(state: GraphState) -> str:
    print("--- (Node 4) 분기 결정 ---")
    if not state.get('top_docs'):
        print("     -> 1차 검색 결과 없음. 바로 답변 생성으로 이동합니다.")
        return "generate_answer_direct"

    top_doc_source = state['top_docs'][0].metadata['source']
    connected_nodes = state['connected_nodes']
    
    if top_doc_source in connected_nodes:
        print(f"     -> '{top_doc_source}'는 연결된 노드. 2차 검색으로 확장합니다.")
        return "expand_context"
    else:
        print(f"     -> '{top_doc_source}'는 고립된 노드. 바로 답변 생성으로 이동합니다.")
        return "generate_answer_direct"

def second_pass_retrieval(state: GraphState) -> dict:
    print("--- (Node 5a) 2차 검색 (문맥 확장) ---")
    question = state['question']
    top_doc_source = state['top_docs'][0].metadata['source']
    edges = state['edges']
    db_path = _get_db_path()

    query_embedding_function = GoogleGenerativeAIEmbeddings(model=EMBEDDING_MODEL, task_type="retrieval_query")
    vectorstore = Chroma(
        persist_directory=db_path,
        embedding_function=query_embedding_function
    )
    
    neighbors = {edge['to'] for edge in edges if edge['from'] == top_doc_source}
    neighbors.update({edge['from'] for edge in edges if edge['to'] == top_doc_source})
            
    print(f"     - '{top_doc_source}'의 이웃 노드 {len(neighbors)}개를 대상으로 추가 검색...")
    
    if not neighbors:
        return {"expanded_docs": []}

    retriever = vectorstore.as_retriever(
        search_kwargs={"k": 2, "filter": {"source": {"$in": list(neighbors)}}}
    )
    expanded_docs = retriever.invoke(question)
    
    print(f"     - 2차 검색 결과: {[doc.metadata['source'] for doc in expanded_docs]}")
    return {"expanded_docs": expanded_docs}

def generate_answer(state: GraphState) -> dict:
    print("--- (Node 6) 최종 답변 생성 ---")
    
    # --- [수정] --- 'question' 대신 'original_question'을 사용하도록 변경
    question_for_llm = state['original_question']
    top_docs = state.get('top_docs') or []
    expanded_docs = state.get('expanded_docs') or []

    combined_docs = top_docs + expanded_docs
    unique_docs_map = { (doc.metadata['source'], doc.page_content): doc for doc in combined_docs }
    final_docs = list(unique_docs_map.values())

    if not final_docs:
        return {"answer": "죄송합니다, 관련 정보를 노트에서 찾을 수 없습니다.", "sources": []}

    context_parts = []
    for doc in final_docs:
        source_file = doc.metadata.get('source', '알 수 없는 출처')
        original_content = doc.metadata.get('original_content', doc.page_content)
        
        context_part = (
            f"문서명: {source_file}\n"
            f"--- 전체 내용 ---\n{original_content}\n"
            f"--- 검색된 관련 부분 ---\n{doc.page_content}"
        )
        context_parts.append(context_part)
        
    context_text = "\n\n---\n\n".join(context_parts)
    
    prompt_template = PROMPT_TEMPLATES["generate_answer"]
    
    llm = ChatGoogleGenerativeAI(model=DEFAULT_GEMINI_MODEL, temperature=0.3)
    
    chain = prompt_template | llm | StrOutputParser()

    # --- [수정] --- 최종 LLM 호출 시 원본 질문을 전달
    answer = chain.invoke({"context": context_text, "question": question_for_llm})
    
    source_names = sorted(list(set([doc.metadata['source'] for doc in final_docs])))
    
    print(f"--- 답변 생성 완료 (참조: {source_names}) ---")
    return {"final_context": context_text, "answer": answer, "sources": source_names}

def build_rag_workflow():
    workflow = StateGraph(GraphState)
    workflow.add_node("expand_notes", expand_short_notes)
    # --- [수정] --- 노드 이름 변경
    workflow.add_node("generate_hyde", generate_hypothetical_document)
    workflow.add_node("prepare", prepare_retrieval)
    workflow.add_node("first_retrieval", first_pass_retrieval)
    workflow.add_node("expand_retrieval", second_pass_retrieval)
    workflow.add_node("generate", generate_answer)

    workflow.set_entry_point("expand_notes")
    # --- [수정] --- 엣지 연결 순서 변경
    workflow.add_edge("expand_notes", "generate_hyde")
    workflow.add_edge("generate_hyde", "prepare")
    workflow.add_edge("prepare", "first_retrieval")
    
    workflow.add_conditional_edges(
        "first_retrieval",
        analyze_and_branch,
        {
            "expand_context": "expand_retrieval",
            "generate_answer_direct": "generate"
        }
    )
    
    workflow.add_edge("expand_retrieval", "generate")
    workflow.add_edge("generate", END)

    return workflow.compile()