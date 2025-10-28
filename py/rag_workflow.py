# py/rag_workflow.py

import os
import platform
from pathlib import Path
from langchain_chroma import Chroma
from langchain_google_genai import GoogleGenerativeAIEmbeddings, ChatGoogleGenerativeAI
from langchain.prompts import ChatPromptTemplate
from langchain.schema.output_parser import StrOutputParser
from langchain.schema.document import Document
from langchain.text_splitter import RecursiveCharacterTextSplitter
from gemini_ai import EMBEDDING_MODEL, DEFAULT_GEMINI_MODEL

from typing import TypedDict, List
from langgraph.graph import StateGraph, END

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

# JSON 경로 함수는 현재 코드에서 사용되지 않으므로 삭제해도 무방합니다.
# def _get_json_path() -> str: ...

class GraphState(TypedDict):
    """
    LangGraph의 상태를 정의하는 TypedDict입니다.
    워크플로우의 각 노드 간에 데이터가 이 구조를 통해 전달됩니다.
    """
    # 필수 입력 값
    question: str
    notes: List[dict]
    edges: List[dict]
    
    # 노드 실행 결과로 채워지는 값
    documents: List[Document]
    vectorstore: Chroma
    top_docs: List[Document]
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

        --- 노트 내용 ---
        {context}
        ---

        질문: {question}

        답변:"""
    ),
    "validate_documents": ChatPromptTemplate.from_template(
        """당신은 주어진 문서가 사용자의 질문에 답변하는 데 도움이 될지 평가하는 전문가입니다.
        아래 "질문"과 "문서 목록"을 검토해주세요.

        "질문"에 답변하는 데 도움이 될 것이라고 생각하는 모든 '문서 번호'를 쉼표로 구분하여 나열해주세요.
        도움이 되는 문서가 하나도 없다면 'None'이라고만 답변해주세요.
        다른 설명은 절대 추가하지 마세요.

        --- 질문 ---
        {question}

        --- 문서 목록 ---
        {documents}

        --- 도움이 되는 문서 번호 ---
        """
    )
}

def validate_retrieved_documents(state: GraphState) -> dict:
    print("--- (Node 4) 검색된 문서 유효성 검증 ---")
    question = state['question']
    top_docs = state['top_docs']
    
    # 검증할 문서가 없으면 바로 종료
    if not top_docs:
        print("     - 유효성을 검증할 문서가 없습니다.")
        return {"top_docs": []}

    # 상위 4개 문서만 선택
    docs_to_validate = top_docs[:4]
    
    validation_model_name = "gemini-2.5-flash-lite" 
    llm = ChatGoogleGenerativeAI(model=validation_model_name, temperature=0)
    prompt = PROMPT_TEMPLATES["validate_documents"]
    chain = prompt | llm | StrOutputParser()
    
    # LLM에 전달할 형식으로 문서 포맷팅
    formatted_docs = []
    for i, doc in enumerate(docs_to_validate):
        formatted_docs.append(f"문서 번호: {i}\n내용: {doc.page_content}\n---")
    documents_str = "\n".join(formatted_docs)
    
    try:
        response = chain.invoke({"question": question, "documents": documents_str})
        print(f"     - 유효성 검증 모델 응답: '{response}'")
        
        if response.strip().lower() == 'none':
            print("     - 모든 문서가 질문과 관련이 없는 것으로 판단되었습니다.")
            return {"top_docs": []}
        
        # 유효한 문서 인덱스 파싱
        valid_indices = [int(i.strip()) for i in response.split(',') if i.strip().isdigit()]
        
        # 유효한 인덱스에 해당하는 문서만 필터링
        validated_docs = [docs_to_validate[i] for i in valid_indices if 0 <= i < len(docs_to_validate)]
        
        validated_sources = [doc.metadata['source'] for doc in validated_docs]
        print(f"     - 유효성 검증 통과 문서: {validated_sources}")
        
        return {"top_docs": validated_docs}
            
    except Exception as e:
        print(f"     - 문서 유효성 검증 중 오류 발생: {e}. 모든 문서를 유효한 것으로 간주합니다.")
        # 오류 발생 시에는 상위 4개 문서를 그대로 반환하여 답변 생성 시도
        return {"top_docs": docs_to_validate}

def expand_short_notes(state: GraphState) -> dict:
    print("--- (Node 0) 짧은 메모 보강 시작 ---")
    notes = state['notes']
    MIN_CHARS_FOR_EXPANSION = 100
    updated_notes = []
    
    llm = ChatGoogleGenerativeAI(model=DEFAULT_GEMINI_MODEL, temperature=0.5)
    prompt = PROMPT_TEMPLATES["expand_note"]
    chain = prompt | llm | StrOutputParser()

    for note in notes:
        # 'retrieval_content'를 새로 만들어 검색용으로 사용하고, 'content'는 원본을 보존
        if len(note['content']) < MIN_CHARS_FOR_EXPANSION:
            print(f"     - '{note['fileName']}' 보강 필요 (현재 {len(note['content'])}자)")
            expanded_content = chain.invoke({"original_content": note['content']})
            note['retrieval_content'] = expanded_content
            print(f"     - 보강 완료: {expanded_content[:50]}...")
        else:
            note['retrieval_content'] = note['content'] # 내용이 충분하면 원본을 그대로 사용
        updated_notes.append(note)
        
    return {"notes": updated_notes}

def expand_question(state: GraphState) -> dict:
    print("--- (Node 1) 질문 확장 시작 ---")
    original_question = state['question']
    
    llm = ChatGoogleGenerativeAI(model=DEFAULT_GEMINI_MODEL, temperature=0)
    prompt = PROMPT_TEMPLATES["expand_question"]
    chain = prompt | llm | StrOutputParser()
    
    expanded_question = chain.invoke({"question": original_question})
    print(f"     - 원본 질문: \"{original_question}\"")
    print(f"     - 확장된 질문: \"{expanded_question}\"")
    
    # 확장된 질문으로 state의 'question'을 업데이트
    return {"question": expanded_question}

def prepare_retrieval(state: GraphState) -> dict:
    print("--- (Node 2) 검색 준비, 벡터 저장소 로드 및 업데이트 ---")
    notes = state['notes']
    edges = state['edges']
    db_path = _get_db_path()

    embedding_function = GoogleGenerativeAIEmbeddings(model=EMBEDDING_MODEL, task_type="retrieval_document")
    vectorstore = Chroma(persist_directory=db_path, embedding_function=embedding_function)
    
    all_note_ids = {note['fileName'] for note in notes}
    # DB에 이미 존재하는 ID를 확인하여 추가할 노트만 필터링 (청크 ID 기준)
    existing_ids_in_db = set(vectorstore.get()['ids'])
    
    notes_to_add = []
    for note in notes:
        # 해당 노트의 청크가 하나라도 DB에 없다면 추가 대상으로 간주
        # (간단한 체크를 위해 첫번째 청크 ID만 확인)
        potential_chunk_id = f"{note['fileName']}_0"
        if potential_chunk_id not in existing_ids_in_db:
            notes_to_add.append(note)

    if notes_to_add:
        print(f"     - {len(notes_to_add)}개의 신규/업데이트 메모를 발견하여 DB에 추가합니다.")
        text_splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)
        
        all_chunks = []
        for note in notes_to_add:
            chunks = text_splitter.split_text(note['retrieval_content'])
            for i, chunk_text in enumerate(chunks):
                chunk_doc = Document(
                    page_content=chunk_text,
                    metadata={'source': note['fileName'], 'original_content': note['content']}
                )
                chunk_id = f"{note['fileName']}_{i}"
                all_chunks.append((chunk_id, chunk_doc))

        if all_chunks:
            ids_to_add = [c[0] for c in all_chunks]
            docs_to_add = [c[1] for c in all_chunks]
            vectorstore.add_documents(documents=docs_to_add, ids=ids_to_add)
            print(f"     - 신규 메모 {len(notes_to_add)}개를 총 {len(all_chunks)}개의 청크로 분할하여 ChromaDB에 추가했습니다.")
    
    return {"vectorstore": vectorstore}

def first_pass_retrieval(state: GraphState) -> dict:
    print("--- (Node 3) 1차 검색 수행 ---")
    question = state['question']
    vectorstore = state['vectorstore']

    if not vectorstore or vectorstore._collection.count() == 0:
        print("     - 벡터 저장소가 비어있어 검색을 건너뜁니다.")
        return {"top_docs": []}

    retriever = vectorstore.as_retriever(search_kwargs={"k": 10})
    top_docs = retriever.invoke(question)
    
    print(f"     - 1차 검색 결과 (상위 {len(top_docs)}개): {[doc.metadata['source'] for doc in top_docs]}")
    return {"top_docs": top_docs}

def generate_answer(state: GraphState) -> dict:
    print("--- (Node 6) 최종 답변 생성 ---")
    question = state['question']
    top_docs = state.get('top_docs', [])

    unique_docs_map = {(doc.metadata['source'], doc.page_content): doc for doc in top_docs}
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
    
    answer = chain.invoke({"context": context_text, "question": question})
    
    source_names = sorted(list(set([doc.metadata['source'] for doc in final_docs])))
    
    print(f"--- 답변 생성 완료 (참조: {source_names}) ---")
    return {"final_context": context_text, "answer": answer, "sources": source_names}

def build_rag_workflow():
    workflow = StateGraph(GraphState)
    
    workflow.add_node("expand_notes", expand_short_notes)
    workflow.add_node("expand_question", expand_question)
    workflow.add_node("prepare", prepare_retrieval)
    workflow.add_node("first_retrieval", first_pass_retrieval)
    workflow.add_node("validate_documents", validate_retrieved_documents)
    workflow.add_node("generate", generate_answer)

    workflow.set_entry_point("expand_notes")
    workflow.add_edge("expand_notes", "expand_question")
    workflow.add_edge("expand_question", "prepare")
    workflow.add_edge("prepare", "first_retrieval")
    workflow.add_edge("first_retrieval", "validate_documents")
    workflow.add_edge("validate_documents", "generate")
    workflow.add_edge("generate", END)

    return workflow.compile()