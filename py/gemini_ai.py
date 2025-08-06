import os
import json
import datetime
import traceback
from dotenv import load_dotenv
import google.generativeai as genai

# --- 1. 초기 설정: API 키 및 모델 설정 ---
load_dotenv()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

if not GEMINI_API_KEY:
    raise ValueError("GEMINI_API_KEY가 .env 파일에 설정되지 않았습니다.")

genai.configure(api_key=GEMINI_API_KEY)

DEFAULT_GEMINI_MODEL = "gemini-1.5-flash"
EMBEDDING_MODEL = "models/text-embedding-004"

# --- 2. 핵심 기능 함수: Gemini API 호출 ---

def get_embedding_for_text(text: str, task_type: str = "retrieval_document") -> list[float] | None:
    """
    하나의 텍스트를 임베딩 벡터로 변환합니다.
    """
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

# [수정] app.py에서 필요한 get_embeddings_batch 함수를 추가합니다.
def get_embeddings_batch(texts: list[str], model_name: str = EMBEDDING_MODEL, task_type: str = "retrieval_document") -> list[list[float]]:
    """
    여러 텍스트를 한 번의 API 호출로 임베딩합니다. (효율성 증대)
    """
    try:
        # texts 목록에서 비어있는 문자열을 API 오류 방지를 위해 공백 한 칸으로 대체
        processed_texts = [text if text.strip() else " " for text in texts]
        result = genai.embed_content(
            model=model_name,
            content=processed_texts,
            task_type=task_type
        )
        return result['embedding']
    except Exception as e:
        print(f"배치 임베딩 중 오류 발생: {e}")
        # 오류 발생 시, 각 텍스트에 대해 빈 리스트를 반환하여 일부라도 처리되도록 함
        return [[] for _ in texts]

def query_gemini(prompt: str, model_name: str = DEFAULT_GEMINI_MODEL) -> str:
    """
    Gemini 생성 모델에 프롬프트를 보내고 텍스트 응답을 받습니다.
    """
    try:
        model = genai.GenerativeModel(model_name)
        response = model.generate_content(prompt)
        
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

# --- 3. 작업별 유틸리티 함수 ---

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
    """
    요약, 메모, 키워드 추출 등 간단한 작업을 수행합니다.
    """
    if task_type not in task_prompts:
        return f"Error: 지원하지 않는 작업 유형입니다: {task_type}"
    
    prompt = task_prompts[task_type].replace("[TEXT]", text)
    return query_gemini(prompt)

# --- 메인 실행 블록 (테스트용) ---
if __name__ == '__main__':
    print("--- gemini_ai.py 모듈 테스트 시작 ---")

    # 1. 임베딩 기능 테스트
    print("\n[1. 임베딩 테스트]")
    sample_text_for_embedding = "오늘 회의에서는 다음 분기 마케팅 전략을 논의했다."
    embedding_vector = get_embedding_for_text(sample_text_for_embedding)
    if embedding_vector:
        print(f"입력 텍스트: \"{sample_text_for_embedding}\"")
        print(f"임베딩 벡터 차원: {len(embedding_vector)}")
        print(f"벡터 앞 5개 값: {embedding_vector[:5]}")
    else:
        print("임베딩 테스트 실패.")

    # 2. 요약 기능 테스트
    print("\n[2. 요약 기능 테스트]")
    sample_text_for_summary = """
    플러터는 구글이 개발한 오픈소스 UI 소프트웨어 개발 키트입니다. 
    하나의 코드베이스로 안드로이드, iOS, 웹, 데스크톱용 네이티브 애플리케이션을 개발할 수 있습니다.
    핫 리로드 기능을 통해 개발자는 코드 변경 사항을 앱에 즉시 반영하여 빠르게 프로토타이핑하고 반복 작업을 수행할 수 있습니다.
    이는 개발 생산성을 크게 향상시키는 주요 요인 중 하나입니다.
    """
    summary_result = execute_simple_task("summarize", sample_text_for_summary)
    print(f"입력 텍스트:\n{sample_text_for_summary.strip()}")
    print("-" * 20)
    print(f"요약 결과:\n{summary_result}")

    # 3. 키워드 추출 테스트
    print("\n[3. 키워드 추출 테스트]")
    keyword_result = execute_simple_task("keyword", sample_text_for_summary)
    print(f"입력 텍스트:\n{sample_text_for_summary.strip()}")
    print("-" * 20)
    print(f"키워드 추출 결과:\n{keyword_result}")

    print("\n--- gemini_ai.py 모듈 테스트 종료 ---")
