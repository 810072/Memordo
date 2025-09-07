# py/rag_workflow.py

import os
import json
import platform
from pathlib import Path
from dotenv import load_dotenv
from langchain_community.vectorstores import Chroma
from langchain_google_genai import GoogleGenerativeAIEmbeddings
from langchain.prompts import ChatPromptTemplate
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain.schema.output_parser import StrOutputParser
from langchain.schema.document import Document

from typing import TypedDict, List
from langgraph.graph import StateGraph, END

load_dotenv()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

def _get_embeddings_path() -> str:
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

# (expand_short_notes, expand_question 함수는 이전과 동일)
def expand_short_notes(state: GraphState) -> dict:
    print("--- (Node 0) 짧은 메모 보강 시작 ---")
    notes = state['notes']
    MIN_CHARS_FOR_EXPANSION = 100
    updated_notes = []
    llm = ChatGoogleGenerativeAI(model="gemini-2.5-flash", temperature=0.5, google_api_key=GEMINI_API_KEY)
    prompt = ChatPromptTemplate.from_template(
        """다음 메모는 내용이 너무 짧아 문맥이 부족합니다.
        메모의 핵심 의미를 유지하면서, 이 메모가 어떤 상황에서 작성되었을지 추론하여 내용을 보강해주세요.
        보강된 내용만 간결하게 답변해주세요.
        
        --- 원본 메모 ---
        {original_content}
        """
    )
    chain = prompt | llm | StrOutputParser()
    for note in notes:
        if len(note['content']) < MIN_CHARS_FOR_EXPANSION:
            print(f"    - '{note['fileName']}' 보강 필요 (현재 {len(note['content'])}자)")
            expanded_content = chain.invoke({"original_content": note['content']})
            note['content'] = expanded_content
            print(f"    - 보강 완료: {expanded_content[:50]}...")
        updated_notes.append(note)
    return {"notes": updated_notes}

def expand_question(state: GraphState) -> dict:
    print("--- (Node 1) 질문 확장 시작 ---")
    original_question = state['question']
    llm = ChatGoogleGenerativeAI(model="gemini-2.5-flash", temperature=0, google_api_key=GEMINI_API_KEY)
    prompt = ChatPromptTemplate.from_template(
        """당신은 사용자의 질문을 벡터 검색에 더 적합하도록 재작성하는 전문가입니다.
        질문의 핵심 의도는 유지하되, 가능한 상세하고 구체적인 정보(예: 주제, 맥락, 예상 답변 형식)를 포함하는 풍부한 문장으로 만들어주세요.
        재작성된 질문만 간결하게 답변해주세요.

        --- 원본 질문 ---
        {question}
        """
    )
    chain = prompt | llm | StrOutputParser()
    expanded_question = chain.invoke({"question": original_question})
    print(f"    - 원본 질문: \"{original_question}\"")
    print(f"    - 확장된 질문: \"{expanded_question}\"")
    return {"question": expanded_question}

def prepare_retrieval(state: GraphState) -> dict:
    """[FIXED] 복잡한 embeddings.json 구조를 파싱하고, 신규 메모를 자동으로 임베딩하며 캐시를 업데이트합니다."""
    print("--- (Node 2) 검색 준비 및 그룹 분류 (신규 메모 자동 임베딩) ---")
    notes = state['notes']
    edges = state['edges']
    embeddings_path = _get_embeddings_path()
    
    embedding_data = []
    embedding_map = {}
    try:
        if os.path.exists(embeddings_path) and os.path.getsize(embeddings_path) > 0:
            with open(embeddings_path, 'r', encoding='utf-8') as f:
                loaded_json = json.load(f)
                # [FIX] 복잡한 JSON 구조에서 'embeddings' 키에 해당하는 데이터만 추출
                if isinstance(loaded_json, dict) and 'embeddings' in loaded_json:
                    embeddings_dict = loaded_json.get('embeddings', {})
                    # 맵과 리스트 데이터 구조를 재구성
                    for fileName, data in embeddings_dict.items():
                        if 'vector' in data:
                            embedding_map[fileName] = data['vector']
                            embedding_data.append({'fileName': fileName, 'embedding': data['vector']})
                    print(f"    - '{embeddings_path}'에서 {len(embedding_data)}개 임베딩 정보 로드 완료.")
                else:
                    print(f"    - 경고: '{embeddings_path}'에 'embeddings' 키가 없거나 형식이 잘못되었습니다.")
    except Exception as e:
        print(f"    - 경고: '{embeddings_path}' 파일을 처리하는 중 오류 발생: {e}")

    notes_to_embed = [note for note in notes if note['fileName'] not in embedding_map]
    
    if notes_to_embed:
        print(f"    - {len(notes_to_embed)}개의 신규 메모를 발견하여 임베딩을 생성합니다.")
        embedding_function_doc = GoogleGenerativeAIEmbeddings(model="models/embedding-001", task_type="retrieval_document", google_api_key=GEMINI_API_KEY)
        
        contents_to_embed = [note['content'] for note in notes_to_embed]
        new_embeddings = embedding_function_doc.embed_documents(contents_to_embed)
        
        for i, note in enumerate(notes_to_embed):
            file_name = note['fileName']
            new_embedding_entry = {'fileName': file_name, 'embedding': new_embeddings[i]}
            embedding_data.append(new_embedding_entry)
            embedding_map[file_name] = new_embeddings[i]
        
        # [FIXED] 더 단순하고 안정적인 리스트 형태로 파일 저장
        try:
            with open(embeddings_path, 'w', encoding='utf-8') as f:
                json.dump(embedding_data, f, ensure_ascii=False, indent=4)
            print(f"    - '{embeddings_path}'에 단순화된 형식으로 임베딩 정보 저장 완료.")
        except Exception as e:
            print(f"    - 에러: '{embeddings_path}' 파일 저장에 실패했습니다: {e}")

    documents, texts_for_db, embeddings_for_db, metadatas_for_db = [], [], [], []
    for note in notes:
        file_name = note['fileName']
        if file_name in embedding_map:
            documents.append(Document(page_content=note['content'], metadata={'source': file_name}))
            texts_for_db.append(note['content'])
            embeddings_for_db.append(embedding_map[file_name])
            metadatas_for_db.append({'source': file_name})

    embedding_function_query = GoogleGenerativeAIEmbeddings(model="models/embedding-001", task_type="retrieval_query", google_api_key=GEMINI_API_KEY)
    vectorstore = Chroma(embedding_function=embedding_function_query)
    
    if texts_for_db:
        vectorstore.add_texts(texts=texts_for_db, embeddings=embeddings_for_db, metadatas=metadatas_for_db)
        print(f"    - {len(texts_for_db)}개의 문서를 ChromaDB에 추가 완료.")

    connected_nodes = {edge['from'] for edge in edges} | {edge['to'] for edge in edges}
    all_nodes = {note['fileName'] for note in notes}
    isolated_nodes = all_nodes - connected_nodes
    
    print(f"    - 연결된 노드: {len(connected_nodes)}개, 고립된 노드: {len(isolated_nodes)}개")
    
    return {
        "documents": documents, "vectorstore": vectorstore,
        "connected_nodes": connected_nodes, "isolated_nodes": isolated_nodes,
    }

# (이하 first_pass_retrieval, analyze_and_branch, second_pass_retrieval, generate_answer, build_rag_workflow 함수는 이전과 동일합니다.)

def first_pass_retrieval(state: GraphState) -> dict:
    print("--- (Node 3) 1차 검색 수행 ---")
    question = state['question']
    vectorstore = state['vectorstore']
    
    if not vectorstore or not hasattr(vectorstore, '_collection') or vectorstore._collection.count() == 0:
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
    vectorstore = state['vectorstore']
    
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
    
    prompt_template = ChatPromptTemplate.from_template(
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
    
    llm = ChatGoogleGenerativeAI(model="gemini-2.5-flash", temperature=0.3, google_api_key=GEMINI_API_KEY)
    
    chain = prompt_template | llm | StrOutputParser()
    answer = chain.invoke({"context": context_text, "question": question})
    
    # [FIX] 소스 문서 목록을 결과에 포함하여 반환
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