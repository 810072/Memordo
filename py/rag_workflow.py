# py/rag_workflow.py

import os
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

# --- 1. 상태 정의 ---
class GraphState(TypedDict):
    question: str
    notes: List[dict]
    edges: List[dict]
    documents: List[Document]
    vectorstore: Chroma
    connected_nodes: set
    isolated_nodes: set
    # [수정] 단일 문서가 아닌 문서 리스트를 저장합니다.
    top_docs: List[Document] 
    expanded_docs: List[Document]
    final_context: str
    answer: str

# --- 2. 노드(함수)들 정의 ---

def prepare_retrieval(state: GraphState) -> dict:
    print("--- (Node 1) 검색 준비 및 그룹 분류 ---")
    notes = state['notes']
    edges = state['edges']
    
    documents = [Document(page_content=note['content'], metadata={'source': note['fileName']}) for note in notes]
    
    connected_nodes = {edge['from'] for edge in edges} | {edge['to'] for edge in edges}
    all_nodes = {note['fileName'] for note in notes}
    isolated_nodes = all_nodes - connected_nodes
    
    print(f"    - 연결된 노드: {len(connected_nodes)}개, 고립된 노드: {len(isolated_nodes)}개")
    
    embedding_function = GoogleGenerativeAIEmbeddings(
        model="models/embedding-001", 
        task_type="retrieval_document",
        google_api_key=GEMINI_API_KEY
    )
    vectorstore = Chroma.from_documents(documents, embedding_function)
    
    return {
        "documents": documents,
        "vectorstore": vectorstore,
        "connected_nodes": connected_nodes,
        "isolated_nodes": isolated_nodes,
    }

def first_pass_retrieval(state: GraphState) -> dict:
    """[수정] 1차 검색: 전체 문서를 대상으로 여러 개(k=3)의 후보를 검색합니다."""
    print("--- (Node 2) 1차 검색 수행 ---")
    question = state['question']
    vectorstore = state['vectorstore']
    
    # k=1에서 k=3으로 변경하여 3개의 후보 문서를 가져옵니다.
    retriever = vectorstore.as_retriever(search_kwargs={"k": 3})
    top_docs = retriever.invoke(question)
    
    print(f"    - 1차 검색 결과 (상위 3개): {[doc.metadata['source'] for doc in top_docs]}")
    return {"top_docs": top_docs}

def analyze_and_branch(state: GraphState) -> str:
    """[수정] 검색된 최상위 문서(첫 번째 후보)가 '허브'인지 '고립'인지 판단하여 분기합니다."""
    print("--- (Node 3) 분기 결정 ---")
    # 후보가 없는 경우를 대비
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
    """[수정] 최상위 문서의 이웃 노드들 내에서만 검색합니다."""
    print("--- (Node 4a) 2차 검색 (문맥 확장) ---")
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
    """[수정] 최종 컨텍스트를 구성하고 LLM으로 답변 생성합니다."""
    print("--- (Node 5) 최종 답변 생성 ---")
    question = state['question']
    # 1차 검색 결과 전체를 기본 컨텍스트로 사용합니다.
    top_docs = state.get('top_docs', [])
    expanded_docs = state.get('expanded_docs', [])

    # 중복을 제거하면서 최종 컨텍스트 구성
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
    
    llm = ChatGoogleGenerativeAI(model="gemini-1.5-flash", temperature=0.3, google_api_key=GEMINI_API_KEY)
    
    chain = prompt_template | llm | StrOutputParser()
    answer = chain.invoke({"context": context_text, "question": question})
    
    print("--- 답변 생성 완료 ---")
    return {"final_context": context_text, "answer": answer}

# --- 3. 워크플로우 빌더 함수 (기존과 동일) ---
def build_rag_workflow():
    workflow = StateGraph(GraphState)

    workflow.add_node("prepare", prepare_retrieval)
    workflow.add_node("first_retrieval", first_pass_retrieval)
    workflow.add_node("expand_retrieval", second_pass_retrieval)
    workflow.add_node("generate", generate_answer)

    workflow.set_entry_point("prepare")
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