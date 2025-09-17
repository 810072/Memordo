# py/rag_workflow.py

import os
import json
import platform
from pathlib import Path
# from dotenv import load_dotenv # --- 삭제 ---
from langchain_community.vectorstores import Chroma
from langchain_google_genai import GoogleGenerativeAIEmbeddings
from langchain.prompts import ChatPromptTemplate
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain.schema.output_parser import StrOutputParser
from langchain.schema.document import Document

from gemini_ai import EMBEDDING_MODEL, DEFAULT_GEMINI_MODEL

from typing import TypedDict, List
from langgraph.graph import StateGraph, END

# --- 삭제 ---
# load_dotenv()
# GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
# --- 삭제 ---


def _get_db_path() -> str:
    """실행 중인 OS를 감지하여 ChromaDB 저장소의 동적 경로를 반환합니다."""
    home_dir = Path.home()
    system = platform.system()
    if system == "Darwin": # macOS
        notes_dir = home_dir / "Memordo_Notes"
    else: # Windows, Linux 등
        notes_dir = home_dir / "Documents" / "Memordo_Notes"
    
    db_path = notes_dir / "chroma_db"
    os.makedirs(db_path, exist_ok=True)
    return str(db_path)

def _get_json_path() -> str:
    """실행 중인 OS를 감지하여 embeddings.json 파일의 동적 경로를 반환합니다."""
    home_dir = Path.home()
    system = platform.system()
    if system == "Darwin": # macOS
        notes_dir = home_dir / "Memordo_Notes"
    else: # Windows, Linux 등
        notes_dir = home_dir / "Documents" / "Memordo_Notes"
    
    os.makedirs(notes_dir, exist_ok=True)
    return str(notes_dir / "embeddings.json")

class GraphState(TypedDict):
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
    "expand_question": ChatPromptTemplate.from_template(
        """당신은 사용자의 질문을 벡터 검색에 더 적합하도록 재작성하는 전문가입니다.
        질문의 핵심 의도는 유지하되, 가능한 상세하고 구체적인 정보(예: 주제, 맥락, 예상 답변 형식)를 포함하는 풍부한 문장으로 만들어주세요.
        재작성된 질문만 간결하게 답변해주세요.

        --- 원본 질문 ---
        {question}
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
    # --- 수정: google_api_key 인자 제거 ---
    llm = ChatGoogleGenerativeAI(model=DEFAULT_GEMINI_MODEL, temperature=0.5)
    prompt = PROMPT_TEMPLATES["expand_note"]
    chain = prompt | llm | StrOutputParser()
    for note in notes:
        # [수정] 원본 보존: 'retrieval_content'를 새로 만들어 검색용으로 사용하고, 'content'는 수정하지 않음
        if len(note['content']) < MIN_CHARS_FOR_EXPANSION:
            print(f"    - '{note['fileName']}' 보강 필요 (현재 {len(note['content'])}자)")
            expanded_content = chain.invoke({"original_content": note['content']})
            note['retrieval_content'] = expanded_content
            print(f"    - 보강 완료: {expanded_content[:50]}...")
        else:
            note['retrieval_content'] = note['content'] # 내용이 충분한 노트는 원본을 그대로 사용
        updated_notes.append(note)
    return {"notes": updated_notes}

def expand_question(state: GraphState) -> dict:
    print("--- (Node 1) 질문 확장 시작 ---")
    original_question = state['question']
    # --- 수정: google_api_key 인자 제거 ---
    llm = ChatGoogleGenerativeAI(model=DEFAULT_GEMINI_MODEL, temperature=0)
    prompt = PROMPT_TEMPLATES["expand_question"]
    chain = prompt | llm | StrOutputParser()
    expanded_question = chain.invoke({"question": original_question})
    print(f"    - 원본 질문: \"{original_question}\"")
    print(f"    - 확장된 질문: \"{expanded_question}\"")
    return {"question": expanded_question}

def prepare_retrieval(state: GraphState) -> dict:
    """[REFACTORED] ChromaDB를 기본 저장소로 사용하고, graph_page 호환성을 위해 embeddings.json도 함께 업데이트합니다."""
    print("--- (Node 2) 검색 준비, 벡터 저장소 로드 및 업데이트 ---")
    notes = state['notes']
    edges = state['edges']
    db_path = _get_db_path()
    json_path = _get_json_path()

    # [JSON 로직 복원] 1. 하위 호환성을 위해 기존 embeddings.json 파일 로드
    embedding_data_wrapper = {}
    try:
        if os.path.exists(json_path) and os.path.getsize(json_path) > 0:
            with open(json_path, 'r', encoding='utf-8') as f:
                embedding_data_wrapper = json.load(f)
    except Exception as e:
        print(f"    - 경고: '{json_path}' 파일을 읽는 중 오류 발생: {e}")
    embedding_map = embedding_data_wrapper.get("embeddings", {})

    # [ChromaDB 로직] 2. 영구 저장소를 사용하는 ChromaDB 인스턴스 생성 및 로드
    embedding_function = GoogleGenerativeAIEmbeddings(model=EMBEDDING_MODEL, task_type="retrieval_document")
    vectorstore = Chroma(persist_directory=db_path, embedding_function=embedding_function)
    
    # 3. DB에 이미 저장된 노트 ID 목록과 새로 추가해야 할 노트 식별
    existing_ids_in_db = set(vectorstore.get()['ids'])
    all_note_ids = {note['fileName'] for note in notes}
    notes_to_add_ids = all_note_ids - existing_ids_in_db
    
    if notes_to_add_ids:
        notes_to_add = [note for note in notes if note['fileName'] in notes_to_add_ids]
        print(f"    - {len(notes_to_add)}개의 신규 메모를 발견하여 DB와 JSON에 추가합니다.")

        # 4. 신규 노트 임베딩 생성
        contents_to_embed = [note['retrieval_content'] for note in notes_to_add]
        new_embeddings = embedding_function.embed_documents(contents_to_embed)
        
        # 5. ChromaDB에 신규 노트 추가
        metadatas_to_add = [{'source': note['fileName']} for note in notes_to_add]
        ids_to_add = [note['fileName'] for note in notes_to_add]
        if contents_to_embed:
            vectorstore.add_embeddings(texts=contents_to_embed, embeddings=new_embeddings, metadatas=metadatas_to_add, ids=ids_to_add)
            print(f"    - 신규 메모 {len(ids_to_add)}개를 ChromaDB에 추가했습니다.")

        # [JSON 로직 복원] 6. embeddings.json 데이터 업데이트 및 저장
        for i, note in enumerate(notes_to_add):
            embedding_map[note['fileName']] = {"vector": new_embeddings[i]}
        
        try:
            with open(json_path, 'w', encoding='utf-8') as f:
                json.dump({"embeddings": embedding_map}, f, ensure_ascii=False, indent=4)
            print(f"    - '{json_path}'에 {len(notes_to_add)}개의 신규 임베딩을 추가하여 저장했습니다.")
        except Exception as e:
            print(f"    - 에러: '{json_path}' 파일 저장에 실패했습니다: {e}")

    # 7. 최종 답변 생성을 위한 Document 객체 리스트 준비
    documents = [Document(page_content=note['content'], metadata={'source': note['fileName']}) for note in notes]
    
    # 8. 연결 정보 계산
    connected_nodes = {edge['from'] for edge in edges} | {edge['to'] for edge in edges}
    isolated_nodes = all_note_ids - connected_nodes
    
    print(f"    - 연결된 노드: {len(connected_nodes)}개, 고립된 노드: {len(isolated_nodes)}개")
    
    return {"documents": documents, "vectorstore": vectorstore, "connected_nodes": connected_nodes, "isolated_nodes": isolated_nodes}

def first_pass_retrieval(state: GraphState) -> dict:
    print("--- (Node 3) 1차 검색 수행 ---")
    question = state['question']
    db_path = _get_db_path()

    # [수정] 검색 시에는 'retrieval_query'용 임베딩 함수를 사용하는 것이 성능에 유리함
    query_embedding_function = GoogleGenerativeAIEmbeddings(model=EMBEDDING_MODEL, task_type="retrieval_query")
    vectorstore = Chroma(
        persist_directory=db_path,
        embedding_function=query_embedding_function
    )

    if vectorstore._collection.count() == 0:
         print("    - 벡터 저장소가 비어있어 검색을 건너<binary data, 2 bytes>니다.")
         return {"top_docs": []}

    retriever = vectorstore.as_retriever(search_kwargs={"k": 3})
    top_docs = retriever.invoke(question)
    
    print(f"    - 1차 검색 결과 (상위 3개): {[doc.metadata['source'] for doc in top_docs]}")
    return {"top_docs": top_docs}

def analyze_and_branch(state: GraphState) -> str:
    print("--- (Node 4) 분기 결정 ---")
    if not state['top_docs']:
        print("    -> 1차 검색 결과 없음. 바로 답변 생성으로 이동합니다.")
        return "generate_answer_direct"

    top_doc_source = state['top_docs'][0].metadata['source']
    connected_nodes = state['connected_nodes']
    
    if top_doc_source in connected_nodes:
        print(f"    -> '{top_doc_source}'는 연결된 노드. 2차 검색으로 확장합니다.")
        return "expand_context"
    else:
        print(f"    -> '{top_doc_source}'는 고립된 노드. 바로 답변 생성으로 이동합니다.")
        return "generate_answer_direct"

def second_pass_retrieval(state: GraphState) -> dict:
    print("--- (Node 5a) 2차 검색 (문맥 확장) ---")
    question = state['question']
    top_doc_source = state['top_docs'][0].metadata['source']
    edges = state['edges']
    db_path = _get_db_path()

    # [수정] 검색 시에는 'retrieval_query'용 임베딩 함수를 사용
    query_embedding_function = GoogleGenerativeAIEmbeddings(model=EMBEDDING_MODEL, task_type="retrieval_query")
    vectorstore = Chroma(
        persist_directory=db_path,
        embedding_function=query_embedding_function
    )
    
    neighbors = {edge['to'] for edge in edges if edge['from'] == top_doc_source}
    neighbors.update({edge['from'] for edge in edges if edge['to'] == top_doc_source})
            
    print(f"    - '{top_doc_source}'의 이웃 노드 {len(neighbors)}개를 대상으로 추가 검색...")
    
    if not neighbors:
        return {"expanded_docs": []}

    retriever = vectorstore.as_retriever(
        search_kwargs={"k": 2, "filter": {"source": {"$in": list(neighbors)}}}
    )
    expanded_docs = retriever.invoke(question)
    
    print(f"    - 2차 검색 결과: {[doc.metadata['source'] for doc in expanded_docs]}")
    return {"expanded_docs": expanded_docs}

def generate_answer(state: GraphState) -> dict:
    print("--- (Node 6) 최종 답변 생성 ---")
    question = state['question']
    top_docs = state.get('top_docs', [])
    expanded_docs = state.get('expanded_docs', [])

    final_docs_map = {doc.metadata['source']: doc for doc in top_docs}
    for doc in expanded_docs:
        final_docs_map[doc.metadata['source']] = doc
    
    final_docs = list(final_docs_map.values())

    if not final_docs:
        return {"answer": "죄송합니다, 관련 정보를 노트에서 찾을 수 없습니다."}

    context_text = "\n\n---\n\n".join(
        [f"문서명: {doc.metadata['source']}\n내용:\n{doc.page_content}" for doc in final_docs]
    )
    
    prompt_template = PROMPT_TEMPLATES["generate_answer"]
    
    # --- 수정: google_api_key 인자 제거 ---
    llm = ChatGoogleGenerativeAI(model=DEFAULT_GEMINI_MODEL, temperature=0.3)
    
    chain = prompt_template | llm | StrOutputParser()
    answer = chain.invoke({"context": context_text, "question": question})
    
    source_names = [doc.metadata['source'] for doc in final_docs]
    print(f"--- 답변 생성 완료 (참조: {source_names}) ---")
    return {"final_context": context_text, "answer": answer, "sources": source_names}

def build_rag_workflow():
    workflow = StateGraph(GraphState)
    workflow.add_node("expand_notes", expand_short_notes)
    workflow.add_node("expand_question", expand_question)
    workflow.add_node("prepare", prepare_retrieval)
    workflow.add_node("first_retrieval", first_pass_retrieval)
    workflow.add_node("expand_retrieval", second_pass_retrieval)
    workflow.add_node("generate", generate_answer)

    workflow.set_entry_point("expand_notes")
    workflow.add_edge("expand_notes", "expand_question")
    workflow.add_edge("expand_question", "prepare")
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