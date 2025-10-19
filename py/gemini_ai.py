import os
import json
import datetime
import traceback
import google.generativeai as genai

# --- 1. 초기 설정 (동적 초기화 방식 유지) ---
GEMINI_API_KEY = None
LLM_CLIENT = None

DEFAULT_GEMINI_MODEL = "gemini-2.5-flash"
EMBEDDING_MODEL = "models/text-embedding-004"


def initialize_ai_client(api_key: str) -> bool:
    """
    [핵심] API 키를 외부에서 받아 Gemini 클라이언트를 초기화하고 전역 변수에 저장합니다.
    """
    global GEMINI_API_KEY, LLM_CLIENT
    
    if not api_key or not isinstance(api_key, str):
        print("[오류] 초기화를 위한 유효한 API 키가 제공되지 않았습니다.")
        return False
        
    try:
        genai.configure(api_key=api_key)
        LLM_CLIENT = genai.GenerativeModel(DEFAULT_GEMINI_MODEL)
        GEMINI_API_KEY = api_key
        
        print(f"✅ Gemini AI 클라이언트 초기화 성공 (API 키: {api_key[:5]}...).")
        return True
    except Exception as e:
        print(f"[오류] Gemini 클라이언트 초기화 중 오류 발생: {e}")
        traceback.print_exc()
        return False

# --- 2. 핵심 기능 함수 (안전성 및 효율성 강화) ---

def get_embedding_for_text(text: str, task_type: str = "retrieval_document") -> list[float] | None:
    """
    하나의 텍스트를 임베딩 벡터로 변환합니다.
    """
    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.getenv("GOOGLE_API_KEY")

    if not GEMINI_API_KEY:
        print("[오류] 임베딩 실패: AI 클라이언트가 초기화되지 않았습니다.")
        raise ValueError("AI client has not been initialized. Call initialize_ai_client(api_key) first.")

    if not text or not isinstance(text, str) or not text.strip():
        print("[경고] 임베딩할 텍스트가 비어있습니다.")
        return None
    try:
        result = genai.embed_content(
            model=EMBEDDING_MODEL,
            content=text,
            task_type=task_type,
            title="Memordo Document"
        )
        return result['embedding']
    except Exception as e:
        print(f"[오류] Gemini 임베딩 생성 중 오류: {e}")
        traceback.print_exc()
        return None

def get_embeddings_batch(texts: list[str], model_name: str = EMBEDDING_MODEL, task_type: str = "retrieval_document") -> list[list[float]]:
    """
    여러 텍스트를 한 번의 API 호출로 임베딩합니다.
    """
    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.getenv("GOOGLE_API_KEY")
        
    if not GEMINI_API_KEY:
        print("[오류] 배치 임베딩 실패: AI 클라이언트가 초기화되지 않았습니다.")
        raise ValueError("AI client has not been initialized. Call initialize_ai_client(api_key) first.")

    try:
        processed_texts = [text if text.strip() else " " for text in texts]
        result = genai.embed_content(
            model=model_name,
            content=processed_texts,
            task_type=task_type
        )
        return result['embedding']
    except Exception as e:
        print(f"배치 임베딩 중 오류 발생: {e}")
        return [[] for _ in texts]

def query_gemini(prompt: str, model_name: str = DEFAULT_GEMINI_MODEL) -> str:
    """
    초기화된 전역 생성 모델 클라이언트를 사용하여 프롬프트를 보내고 응답을 받습니다.
    대화 기록 없이 단일 프롬프트만 처리합니다.
    """
    global LLM_CLIENT, GEMINI_API_KEY
    if not LLM_CLIENT:
        api_key = GEMINI_API_KEY or os.getenv("GOOGLE_API_KEY")
        if api_key:
            print("[정보] LLM_CLIENT가 없어 재초기화를 시도합니다.")
            initialize_ai_client(api_key)
        else:
            raise ValueError("AI client has not been initialized and no API key found.")

    if not LLM_CLIENT:
        raise ValueError("AI client could not be initialized.")

    try:
        response = LLM_CLIENT.generate_content(prompt)
        
        if response.parts:
            return response.text.strip()
        elif response.prompt_feedback and response.prompt_feedback.block_reason:
            error_msg = f"콘텐츠 생성 차단됨. 이유: {response.prompt_feedback.block_reason}"
            print(f"[오류] {error_msg}")
            return f"Error: {error_msg}"
        else:
            return "Error: Gemini API로부터 비어있는 응답을 받았습니다."

    except Exception as e:
        error_msg = f"Gemini API 호출 중 예외 발생: {type(e).__name__} - {e}"
        print(f"[오류] {error_msg}")
        traceback.print_exc()
        return f"Error: {error_msg}"


def query_gemini_with_history(current_input: str, messages: list, model_name: str = DEFAULT_GEMINI_MODEL) -> str:
    """
    ✨ [새 함수] 대화 기록을 포함하여 Gemini에 요청합니다.
    
    Args:
        current_input: 현재 사용자 입력
        messages: 대화 기록 [{'role': 'user'/'assistant', 'content': '...'}]
        model_name: 사용할 모델명
    
    Returns:
        AI 응답 텍스트
    """
    global LLM_CLIENT, GEMINI_API_KEY
    if not LLM_CLIENT:
        api_key = GEMINI_API_KEY or os.getenv("GOOGLE_API_KEY")
        if api_key:
            print("[정보] LLM_CLIENT가 없어 재초기화를 시도합니다.")
            initialize_ai_client(api_key)
        else:
            raise ValueError("AI client has not been initialized and no API key found.")

    if not LLM_CLIENT:
        raise ValueError("AI client could not be initialized.")

    try:
        # Gemini Chat API를 위한 메시지 형식 변환
        chat_history = []
        for msg in messages:
            role = msg.get('role', 'user')
            content = msg.get('content', '')
            
            # Gemini는 'user'와 'model'만 지원 (assistant -> model)
            gemini_role = 'model' if role == 'assistant' else 'user'
            chat_history.append({
                'role': gemini_role,
                'parts': [content]
            })
        
        # 현재 입력 추가
        chat_history.append({
            'role': 'user',
            'parts': [current_input]
        })
        
        print(f"[DEBUG] 대화 기록 포함 요청 - 메시지 수: {len(chat_history)}")
        
        # Chat 세션 생성 및 응답 받기
        chat = LLM_CLIENT.start_chat(history=chat_history[:-1])  # 마지막 메시지 제외
        response = chat.send_message(current_input)
        
        if response.parts:
            return response.text.strip()
        elif response.prompt_feedback and response.prompt_feedback.block_reason:
            error_msg = f"콘텐츠 생성 차단됨. 이유: {response.prompt_feedback.block_reason}"
            print(f"[오류] {error_msg}")
            return f"Error: {error_msg}"
        else:
            return "Error: Gemini API로부터 비어있는 응답을 받았습니다."

    except Exception as e:
        error_msg = f"Gemini API (with history) 호출 중 예외 발생: {type(e).__name__} - {e}"
        print(f"[오류] {error_msg}")
        traceback.print_exc()
        return f"Error: {error_msg}"


# --- 3. 작업별 유틸리티 함수 (변경 없음) ---
task_prompts = {
    "summarize": "다음 텍스트를 핵심 내용 중심으로 세 문장으로 간결하게 요약해주세요:\n\n\"\"\"\n[TEXT]\n\"\"\"",
    "memo": "다음 내용을 바탕으로 핵심 아이디어와 결정 사항을 강조하는 글머리 기호(불렛 포인트) 형식으로 정리해주세요:\n\n\"\"\"\n[TEXT]\n\"\"\"",
    "keyword": """다음 텍스트를 분석하여 가장 중요한 핵심 키워드 5개를 추출하고, 각 키워드의 중요도를 0.0에서 1.0 사이의 점수로 평가해주세요.
반드시 다음 형식을 지켜주세요:
- 다른 설명 없이, 한 줄에 하나씩 `키워드: 점수` 형태로만 응답해야 합니다.
- 예시:
인공지능: 0.95
머신러닝: 0.88
데이터 분석: 0.85
클라우드 컴퓨팅: 0.76
자연어 처리: 0.72

분석할 텍스트:
\"\"\"
[TEXT]
\"\"\""""
}

def execute_simple_task(task_type: str, text: str) -> str:
    if task_type not in task_prompts:
        return f"Error: 지원하지 않는 작업 유형입니다: {task_type}"
    
    prompt = task_prompts[task_type].replace("[TEXT]", text)
    return query_gemini(prompt)


# --- 메인 실행 블록 (테스트용 코드 통합 및 강화) ---
if __name__ == '__main__':
    print("--- gemini_ai.py 모듈 테스트 시작 ---")

    test_api_key = input("테스트를 위한 Gemini API 키를 입력하세요: ")

    if initialize_ai_client(test_api_key):
        print("\n[테스트] AI 클라이언트 초기화 성공!")
        
        # 대화 기록 테스트
        print("\n[대화 기록 테스트]")
        test_history = [
            {'role': 'user', 'content': '안녕! 내 이름은 철수야.'},
            {'role': 'assistant', 'content': '안녕하세요 철수님! 반갑습니다.'},
        ]
        response = query_gemini_with_history('내 이름이 뭐였지?', test_history)
        print(f"응답: {response}")

    else:
        print("\n[테스트] AI 클라이언트 초기화 실패. 테스트를 종료합니다.")

    print("\n--- gemini_ai.py 모듈 테스트 종료 ---")