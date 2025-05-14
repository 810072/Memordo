import json
import datetime
import time
import os
from pathlib import Path
import traceback # 상세 오류 로깅용
import re # 점수 추출 등 필요

# --- Gemini API 관련 라이브러리 ---
import google.generativeai as genai

# --- RAG 관련 라이브러리 ---
from sentence_transformers import SentenceTransformer
import chromadb

# --- Gemini API 설정 ---
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY") # 환경 변수에서 API 키 로드
if not GEMINI_API_KEY:
    raise ValueError("GEMINI_API_KEY 환경 변수를 설정해주세요.")
genai.configure(api_key=GEMINI_API_KEY)
DEFAULT_GEMINI_MODEL = "gemini-2.0-flash" # 예시 모델, 필요에 따라 변경

# 경로 설정 (스크립트 위치 기준 상대 경로 또는 필요시 절대 경로 사용)
BASE_DIR = os.path.dirname(os.path.abspath(__file__)) # 스크립트가 있는 디렉토리
DOC_DIR = os.path.join(BASE_DIR, "Doc")      # 문서 디렉토리
LOG_DIR = os.path.join(BASE_DIR, "log")      # 로그 디렉토리
CHROMA_DB_PATH = os.path.join(BASE_DIR, "chroma_db_st_multi") # ChromaDB 저장 경로 (모델 변경으로 경로 수정)
LOG_FILENAME = os.path.join(LOG_DIR, "interaction_log_st_multi_gemini.jsonl") # 로그 파일명 변경

# --- SentenceTransformer 모델 설정 ---
# 다국어 임베딩에 적합한 모델 선택
SBERT_MODEL_NAME = 'paraphrase-multilingual-MiniLM-L12-v2' # 영어 전용 모델에서 다국어 모델로 변경
SBERT_MODEL = None # 전역 변수로 모델 관리

# --- ChromaDB 클라이언트 및 컬렉션 설정 ---
CHROMA_CLIENT = None
CHROMA_COLLECTION_NAME = "documents_ko_sbert_multi" # 컬렉션 이름 변경
CHROMA_COLLECTION = None

# --- 유틸리티 함수: SentenceTransformer 모델 로더 ---
def get_sbert_model():
    global SBERT_MODEL
    if SBERT_MODEL is None:
        try:
            SBERT_MODEL = SentenceTransformer(SBERT_MODEL_NAME)
            print(f"SentenceTransformer 모델 '{SBERT_MODEL_NAME}' 로드 완료.")
        except Exception as e:
            print(f"[치명적 오류] SentenceTransformer 모델 '{SBERT_MODEL_NAME}' 로드 실패: {e}")
            raise SystemExit(f"SBERT 모델 로드 실패: {e}")
    return SBERT_MODEL

# --- 유틸리티 함수: ChromaDB 초기화 ---
def initialize_chromadb():
    global CHROMA_CLIENT, CHROMA_COLLECTION
    if CHROMA_CLIENT is None:
        try:
            os.makedirs(CHROMA_DB_PATH, exist_ok=True)
            CHROMA_CLIENT = chromadb.PersistentClient(path=CHROMA_DB_PATH)
            print(f"ChromaDB 클라이언트 초기화 완료 (저장 경로: {CHROMA_DB_PATH})")
        except Exception as e:
            print(f"[치명적 오류] ChromaDB 클라이언트 초기화 실패: {e}")
            raise SystemExit(f"ChromaDB 클라이언트 초기화 실패: {e}")

    if CHROMA_COLLECTION is None and CHROMA_CLIENT:
        try:
            CHROMA_COLLECTION = CHROMA_CLIENT.get_or_create_collection(name=CHROMA_COLLECTION_NAME)
            print(f"ChromaDB 컬렉션 '{CHROMA_COLLECTION_NAME}' 로드/생성 완료. 현재 아이템 수: {CHROMA_COLLECTION.count()}")
        except Exception as e:
            print(f"[치명적 오류] ChromaDB 컬렉션 '{CHROMA_COLLECTION_NAME}' 가져오기/생성 실패: {e}")
            raise SystemExit(f"ChromaDB 컬렉션 가져오기/생성 실패: {e}")
    return CHROMA_COLLECTION

# --- 임베딩 생성 함수 (SentenceTransformer 사용, 한국어 직접 임베딩) ---
def get_embedding_for_text(text_ko): # 함수명 및 입력 파라미터 변경
    """한국어 텍스트에 대한 SentenceTransformer 임베딩 벡터를 반환."""
    if not text_ko or not isinstance(text_ko, str) or not text_ko.strip():
        return None
    try:
        sbert_model = get_sbert_model()
        embedding = sbert_model.encode(text_ko, convert_to_tensor=False) # numpy array
        return embedding.tolist()
    except Exception as e:
        print(f"[오류] SentenceTransformer 임베딩 생성 중 오류 ('{text_ko[:50]}...'): {e}")
        return None

# --- [신규] Gemini 토큰 카운트 함수 ---
def count_gemini_tokens(model_name, text_or_parts):
    try:
        model = genai.GenerativeModel(model_name)
        return model.count_tokens(text_or_parts).total_tokens
    except Exception as e:
        print(f"[경고] Gemini 토큰 카운트 실패: {e}")
        return -1 # 오류 발생 시 -1 반환

# --- [수정됨] Gemini 쿼리 함수 ---
def query_gemini(prompt, model_name=DEFAULT_GEMINI_MODEL, safety_settings=None, generation_config=None):
    """
    Gemini API에 프롬프트를 보내고 응답을 받습니다.
    토큰 사용량도 계산하여 출력합니다.
    """
    model = genai.GenerativeModel(model_name,
                                  safety_settings=safety_settings,
                                  generation_config=generation_config)

    input_token_count = count_gemini_tokens(model_name, prompt)
    print(f"Gemini API 요청 ({model_name}):")
    print(f"  - 입력 토큰 수 (추정): {input_token_count}")

    try:
        response = model.generate_content(prompt)
        
        output_token_count = 0
        total_token_count = 0

        if response.usage_metadata: # 최신 API 응답 형식
            output_token_count = response.usage_metadata.candidates_token_count
            total_token_count = response.usage_metadata.total_token_count
            # 입력 토큰은 response.usage_metadata.prompt_token_count 로도 확인 가능
            print(f"  - 실제 입력 토큰 수: {response.usage_metadata.prompt_token_count}")
            print(f"  - 출력 토큰 수: {output_token_count}")
            print(f"  - 총 사용 토큰 수: {total_token_count}")
        else: # 구버전 또는 다른 응답 형식 대비 (필요시 조정)
            # Gemini API는 보통 usage_metadata를 제공합니다.
            # 만약 없다면, count_tokens로 출력 텍스트를 다시 세어볼 수 있으나 정확도는 떨어짐.
             if response.text:
                 output_token_count = count_gemini_tokens(model_name, response.text)
                 print(f"  - 출력 토큰 수 (응답 기반 재추정): {output_token_count}")


        # response.text 는 response.candidates[0].content.parts[0].text 와 유사
        if response.parts:
             return response.text.strip() # 가장 일반적인 경우
        elif response.text: # 일부 모델은 response.text로 바로 제공
            return response.text.strip()
        else: # 응답이 비었거나, 차단된 경우 등
            # 차단된 경우 response.prompt_feedback 확인
            if response.prompt_feedback and response.prompt_feedback.block_reason:
                error_msg = f"Error: Gemini API가 콘텐츠 생성을 차단했습니다. 이유: {response.prompt_feedback.block_reason}"
                print(f"[Error] {error_msg}")
                if response.prompt_feedback.safety_ratings:
                    for rating in response.prompt_feedback.safety_ratings:
                        print(f"    - {rating.category}: {rating.probability}")
                return error_msg
            return "Error: Gemini API로부터 예상치 못한 응답 형식 또는 빈 응답."

    except Exception as e:
        error_msg = f"Error: Gemini API 호출 중 오류 발생: {type(e).__name__} - {e}"
        print(f"[Error] {error_msg}")
        traceback.print_exc()
        return error_msg

# --- 작업별 프롬프트 템플릿 ---
# 기존 task_prompts 유지 (Gemini는 한국어 프롬프트의 영어 지시사항도 잘 이해하는 편)
# 최적의 성능을 위해서는 프롬프트를 한국어로 번역하거나 Gemini에 맞게 수정하는 것이 좋음
task_prompts = {
    "classify": """Analyze the following text and classify its primary content type using one of the following labels:
- meeting_notes (Contains discussion points, decisions, action items)
- idea_brainstorming (Lists ideas, free-form thoughts)
- technical_explanation (Describes a process, technology, or method)
- personal_reflection (Personal thoughts, diary-like content)
- todo_list (A list of tasks to be done)
- general_information (Factual information, news summary, etc.)
- other (If none of the above fit well)
Please respond with ONLY the most appropriate label in lowercase English (e.g., meeting_notes).

[TEXT]""",
    "summarize": "다음 텍스트를 주요 내용을 중심으로 세 문장으로 간결하게 요약해주세요:\n[TEXT]", # 한국어 프롬프트로 변경
    "memo": "다음 내용을 바탕으로 핵심 아이디어와 결정 사항을 강조하는 글머리 기호를 만드세요:\n[TEXT]", # 한국어 프롬프트로 변경
    "keyword": """다음 텍스트를 분석하십시오. 주요 주제와 관련된 가장 중요한 키워드 5개를 식별하십시오.
각 키워드에 대해 중요도 점수를 0.0에서 1.0 사이의 소수(예: 0.75, 0.9)로 추정하십시오.
출력 형식 규칙:
1. 정확히 5개의 키워드-점수 쌍을 나열해야 합니다.
2. 각 쌍은 새 줄에 있어야 합니다.
3. 각 줄의 형식은 정확히 `키워드: 점수` 여야 합니다 (예: `인공 지능: 0.95`).
4. 점수는 0.0과 1.0 사이의 소수여야 합니다.
5. 다른 텍스트, 설명, 소개 또는 요약을 포함하지 마십시오. 지정된 형식으로 5개의 키워드-점수 쌍만 출력하십시오.
[TEXT]""", # 한국어 프롬프트로 변경 (기존 영어 프롬프트도 Gemini가 잘 처리할 수 있지만, 일관성을 위해)
    "comparison": """아래는 서로 다른 두 텍스트(텍스트 1과 텍스트 2)에서 추출된 키워드 목록입니다.
이 키워드만을 기준으로 텍스트 1과 텍스트 2 간의 주제 유사성을 평가하십시오.
0.0(유사성 없음)과 1.0(매우 높은 유사성) 사이의 단일 유사성 점수를 제공하십시오.
소수점 이하 두 자리로 반올림된 숫자 점수만 출력하십시오(예: 0.75).
텍스트 1의 키워드:
[KEYWORDS1]
텍스트 2의 키워드:
[KEYWORDS2]""", # 한국어 프롬프트로 변경
    # summarize_info_en -> summarize_info_ko 또는 삭제 (Gemini가 직접 한국어 처리)
    "summarize_info_ko": """다음 텍스트를 읽어주세요. 주요 내용을 요약하여 한국어로 2-3문장으로 작성하고, 언급된 주요 사실 정보(이름, 날짜, 결정, 특정 단계, 장소 등)가 있다면 글머리 기호로 한국어로 나열해주세요. 특정 주요 정보가 없다면 "주요 정보: 없음"이라고 명시해주세요.
요약:
[여기에 요약]
주요 정보:
- [주요 정보 1]
...
[TEXT]"""
}


# --- 내용 유형에 따른 동적 프롬프트 생성 함수 (번역 과정 삭제) ---
def create_adaptive_prompt(user_input_ko, task_type, content_type):
    base_prompt_template = task_prompts[task_type]
    adapted_prompt_template = base_prompt_template

    if task_type == "memo":
        if content_type == "meeting_notes":
            adapted_prompt_template = "다음 회의록을 바탕으로 **주요 논의 사항, 결정된 내용, 실행 항목(담당자가 언급된 경우 포함)**에 대한 명확한 글머리 기호를 작성하세요:\n[TEXT]"
        # ... (다른 content_type에 대한 memo 프롬프트, 한국어로 업데이트 필요) ...
        else:
            adapted_prompt_template = task_prompts["memo"] # 기본 한국어 프롬프트 사용
    elif task_type == "summarize":
        if content_type == "technical_explanation":
            adapted_prompt_template = "다음 기술 문서를 **핵심 목적, 주요 방법론/프로세스(있는 경우), 중요한 결과 또는 결론**에 초점을 맞춰 세 문장으로 요약하세요:\n[TEXT]"
        # ... (다른 content_type에 대한 summarize 프롬프트, 한국어로 업데이트 필요) ...
        else:
            adapted_prompt_template = task_prompts["summarize"] # 기본 한국어 프롬프트 사용

    # user_input_en = translate_text(user_input_ko, 'auto', 'en') # 삭제
    # if user_input_en.startswith("Error"): # 삭제
    #     raise Exception(f"적응형 프롬프트 사용자 입력 번역 실패: {user_input_en}") # 삭제

    final_prompt_ko = adapted_prompt_template.replace("[TEXT]", user_input_ko) # 한국어 프롬프트에 한국어 입력 직접 사용
    return final_prompt_ko

# --- 핵심 실행 로직 함수 (Gemini 호출, 번역 삭제) ---
def execute_gemini_task(korean_prompt, model=DEFAULT_GEMINI_MODEL): # 함수명 및 파라미터 변경
    gemini_response_ko = query_gemini(korean_prompt, model_name=model) # 직접 한국어 프롬프트 전달
    # if gemini_response_ko.startswith("Error"): # query_gemini 내부에서 오류 처리
    #     return gemini_response_ko
    # ollama_response_ko = translate_text(ollama_response_en, 'auto', 'ko') # 삭제
    return gemini_response_ko # Gemini는 한국어 응답을 직접 줄 수 있음

# --- 2단계 실행 함수: 분류 -> 적응형 프롬프트 -> 실행 (번역 삭제) ---
def execute_adaptive_gemini_task(user_input_ko, task_type, model=DEFAULT_GEMINI_MODEL): # 함수명 변경
    content_type = "unknown"
    try:
        print("[1단계] 내용 유형 분석 중...")
        # 분류 프롬프트는 영어로 유지하되, [TEXT] 부분은 한국어로 들어감. Gemini가 처리 가능.
        # 더 나은 결과를 위해 classify 프롬프트도 한국어로 번역하는 것을 권장.
        classify_prompt_with_ko_text = task_prompts['classify'].replace("[TEXT]", user_input_ko)
        # classify_prompt_en = translate_text(classify_prompt_with_ko_text, 'auto', 'en') # 삭제
        # if classify_prompt_en.startswith("Error"): # 삭제
        #     print(f"  [경고] 내용 분석 프롬프트 번역 실패. 기본 프롬프트를 사용합니다.") # 삭제
        # else: # 삭제
        classification_result_en = query_gemini(classify_prompt_with_ko_text, model_name=model) # 직접 전달
        
        if classification_result_en.startswith("Error"):
            print(f"  [경고] 내용 유형 분석 실패: {classification_result_en}. 기본 프롬프트를 사용합니다.")
        else:
            detected_type = classification_result_en.splitlines()[0].strip().lower()
            expected_types = ["meeting_notes", "idea_brainstorming", "technical_explanation",
                              "personal_reflection", "todo_list", "general_information", "other"]
            if detected_type in expected_types:
                content_type = detected_type
                print(f"  감지된 내용 유형: {content_type}")
            elif detected_type :
                content_type = "other"
                print(f"  [정보] 예상치 못한 내용 유형 응답 '{detected_type}' 감지됨. 'other'로 처리.")
            else:
                print(f"  [경고] 내용 유형 분석 결과가 비어있거나 유효하지 않음. 기본 프롬프트를 사용합니다.")
    except Exception as e:
        print(f"  [경고] 내용 유형 분석 중 예외 발생: {type(e).__name__} - {e}. 기본 프롬프트를 사용합니다.")

    final_result_ko = f"Error: Adaptive task '{task_type}' failed before execution."
    try:
        print(f"[2단계] 내용 유형({content_type}) 기반 '{task_type}' 작업 실행 중...")
        final_korean_prompt = create_adaptive_prompt(user_input_ko, task_type, content_type) # 한국어 프롬프트 생성
        if final_korean_prompt.startswith("Error"): # create_adaptive_prompt 내부 오류 가능성 체크 (현재는 없음)
            raise Exception(f"적응형 프롬프트 생성 실패: {final_korean_prompt}")
        final_result_ko = execute_gemini_task(final_korean_prompt, model=model)
        return final_result_ko
    except Exception as e:
        error_msg = f"적응형 작업({task_type}) 처리 중 오류 발생: {type(e).__name__} - {e}."
        print(f"  [오류] {error_msg}")
        print("[Fallback] 기본 프롬프트로 작업 재시도 중...")
        try:
            default_prompt_template_ko = task_prompts[task_type] # 기본 한국어 프롬프트 사용
            # user_input_en = translate_text(user_input_ko, 'auto', 'en') # 삭제
            # if user_input_en.startswith("Error"): # 삭제
            #     return f"오류: Fallback 시 사용자 입력 번역 실패 - {user_input_en}" # 삭제
            default_prompt_ko = default_prompt_template_ko.replace("[TEXT]", user_input_ko)
            fallback_result = execute_gemini_task(default_prompt_ko, model=model)
            return fallback_result
        except Exception as fallback_e:
            return f"오류: Fallback 작업 실행 중 오류 발생 - {type(fallback_e).__name__} - {fallback_e}"


# --- Comparison 기능 함수 (번역 삭제) ---
def perform_comparison_task(model=DEFAULT_GEMINI_MODEL): # 모델 파라미터 변경
    keyword_logs = []
    # ... (로그 파일 읽는 로직은 거의 동일, 'output'이 한국어 키워드라고 가정)
    # 로그 파일에서 'output' 필드가 한국어 키워드 목록을 포함하고 있어야 함.
    # 'keyword' 작업 시 Gemini가 한국어 프롬프트에 따라 한국어 키워드를 생성하거나,
    # 영어 키워드를 생성했다면, 여기서는 그 영어 키워드를 그대로 사용하거나,
    # 사용자가 비교를 위해 한국어 키워드를 원한다면 'keyword' 작업의 프롬프트 수정이 필요할 수 있음.
    # 현재 task_prompts["keyword"]는 영어 키워드를 생성하도록 되어 있으므로,
    # Gemini가 이를 한국어로 바꿔주거나, comparison 프롬프트가 영어 키워드를 처리할 수 있어야 함.
    # 여기서는 task_prompts["comparison"]도 한국어로 변경했으므로, KEYWORDS1/2도 한국어여야 함.
    # 따라서, 'keyword' 작업에서 생성된 output (Gemini 응답)이 한국어 키워드 목록 형태여야 함.
    # 만약 Gemini 'keyword' 프롬프트가 영어 키워드:점수 형태를 반환한다면,
    # comparison 프롬프트도 영어 키워드를 받도록 수정하거나, 키워드 추출 결과를 여기서 한국어로 바꿔야 함.
    # 여기서는 'keyword' 작업 결과가 한국어 키워드:점수 형태라고 가정하고 진행.
    # (기존 코드에서 keyword 작업 후 translate_text(keyword_result_en, "en", "ko") 를 했었음)
    # Gemini가 직접 한국어 키워드를 주도록 프롬프트를 수정하는 것이 가장 깔끔함.
    # task_prompts["keyword"]를 "한국어 키워드: 점수" 형식으로 요청하도록 수정했음.
    try:
        if not os.path.exists(LOG_FILENAME):
            return "[오류] 로그 파일을 찾을 수 없습니다..."
        with open(LOG_FILENAME, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    log_entry = json.loads(line)
                    if (log_entry.get('task') == 'keyword' or \
                        (log_entry.get('task') == 'related_task_vector_rag' and 'query_keywords_ko_for_log' in log_entry)) and \
                        'output' in log_entry and \
                        isinstance(log_entry.get('output'), str) and \
                        ':' in log_entry['output'] and \
                        not log_entry['output'].startswith("Error:"):
                        # 'output'이 한국어 키워드 리스트라고 가정
                        display_name = log_entry.get('input', 'N/A')
                        if log_entry.get('task') == 'related_task_vector_rag':
                            display_name = f"쿼리: {log_entry.get('query_keywords_ko_for_log', 'N/A')}"
                        elif log_entry.get('task') == 'keyword' and 'input' in log_entry:
                                display_name = f"텍스트: {log_entry['input'][:30]}..."
                        
                        keyword_logs.append({
                            "timestamp": log_entry.get('timestamp', 'N/A'),
                            "name": display_name,
                            "output": log_entry['output'] # 한국어 키워드 결과
                        })
                except (json.JSONDecodeError, KeyError, TypeError):
                    continue
                except Exception as e:
                    print(f"[경고] 로그 파일 '{LOG_FILENAME}'의 {line_num}번째 라인 처리 중 오류: {type(e).__name__}")
                    continue
    except FileNotFoundError:
        return "[오류] 로그 파일을 찾을 수 없습니다."
    except Exception as e:
        return f"[오류] 로그 파일 읽기 중 오류 발생: {e}"

    if len(keyword_logs) < 2:
        return f"[오류] 비교할 유효한 키워드 로그가 2개 이상 필요합니다. 현재 {len(keyword_logs)}개."
    # ... (사용자 선택 로직은 기존과 동일) ...
    print("\n--- 비교 가능한 키워드 로그 목록 ---")
    for i, log_data in enumerate(keyword_logs):
        print(f"{i+1}. [{log_data['timestamp']}] {log_data['name']}")
    print("----------------------------------------------")

    selected_indices = []
    while len(selected_indices) < 2:
        try:
            prompt_msg = f"비교할 {'첫' if not selected_indices else '두'} 번째 로그 번호 (1-{len(keyword_logs)}): "
            choice_str = input(prompt_msg).strip()
            if not choice_str: continue
            choice_num = int(choice_str)
            selected_index = choice_num - 1
            if 0 <= selected_index < len(keyword_logs):
                if selected_index not in selected_indices:
                    selected_indices.append(selected_index)
                else:
                    print("[오류] 이미 선택한 로그입니다. 다른 번호를 입력해주세요.")
            else:
                print(f"[오류] 1에서 {len(keyword_logs)} 사이의 번호를 입력해주세요.")
        except ValueError:
            print("[오류] 유효한 숫자를 입력해주세요.")
        except EOFError:
            print("\n입력이 중단되었습니다.")
            return "[알림] 사용자 입력 중단됨."

    log1 = keyword_logs[selected_indices[0]]
    log2 = keyword_logs[selected_indices[1]]
    keywords1_ko = log1['output']
    keywords2_ko = log2['output']
    name1 = log1['name']
    name2 = log2['name']

    print(f"\n--- 선택된 비교 대상 ---")
    print(f"1: {name1}")
    print(f"2: {name2}")
    print("-------------------------")

    try:
        comparison_prompt_ko = task_prompts["comparison"]
        comparison_prompt_ko = comparison_prompt_ko.replace("[KEYWORDS1]", keywords1_ko)
        comparison_prompt_ko = comparison_prompt_ko.replace("[KEYWORDS2]", keywords2_ko)
        # comparison_prompt_en = translate_text(comparison_prompt_ko, 'auto', 'en') # 삭제
        # if comparison_prompt_en.startswith("Error"): # 삭제
        #     raise Exception(f"Comparison 프롬프트 번역 실패: {comparison_prompt_en}") # 삭제

        print(f"\n[comparison] 작업을 Gemini({model})에게 요청합니다...")
        comparison_result_text = query_gemini(comparison_prompt_ko, model_name=model) # 직접 한국어 프롬프트 사용

        if comparison_result_text.startswith("Error"):
            return f"[오류] 유사성 평가 중 오류 발생: {comparison_result_text}"
        
        try:
            score_text = comparison_result_text.strip()
            match = re.search(r"(\d*\.\d+|\d+)", score_text) # Gemini 응답에서 숫자 추출
            if match:
                score = float(match.group(1))
                if 0.0 <= score <= 1.0:
                    return f"'{name1}'와(과) '{name2}' 간의 키워드 기반 유사성 점수: {score:.2f}"
                else:
                    return f"계산된 유사성 점수 ({score:.2f})가 범위(0-1)를 벗어났습니다. 원본 결과: '{score_text}'"
            else:
                return f"유사성 평가 결과 (점수 추출 불가): '{score_text}'"
        except ValueError:
            return f"유사성 평가 결과 (텍스트, 점수 변환 불가): '{comparison_result_text}'"
    except Exception as e:
        return f"[오류] Comparison 작업 처리 중 문제 발생: {type(e).__name__} - {e}"


# --- 문서 관련 함수 (chunk_text_by_sentences는 기존 유지) ---
def get_document_paths(doc_dir):
    # ... (기존과 동일)
    doc_path = Path(doc_dir)
    if not doc_path.is_dir():
        print(f"[오류] 문서 디렉토리 '{doc_dir}'를 찾을 수 없거나 디렉토리가 아닙니다.")
        return []
    return list(doc_path.rglob('*.md'))

def read_document_content(filepath):
    # ... (기존과 동일)
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        print(f"[오류] 파일을 찾을 수 없습니다: {filepath}")
        return None
    except Exception as e:
        print(f"[오류] 파일 읽기 오류 ({filepath}): {e}")
        return None

def chunk_text_by_sentences(text, sentences_per_chunk=5):
    # ... (기존과 동일)
    if not text or not isinstance(text, str) or not text.strip():
        return []    
    delimiters = ".!?\n" 
    sentences = []
    current_sentence = ""
    for char in text:
        current_sentence += char
        if char in delimiters:
            if current_sentence.strip():
                sentences.append(current_sentence.strip())
            current_sentence = ""
    if current_sentence.strip():
        sentences.append(current_sentence.strip())

    if not sentences:
        return [text] 

    chunks = []
    current_chunk_sentences = []
    for i, sentence in enumerate(sentences):
        current_chunk_sentences.append(sentence)
        if (i + 1) % sentences_per_chunk == 0 or (i + 1) == len(sentences):
            chunks.append(" ".join(current_chunk_sentences))
            current_chunk_sentences = []
    return chunks


# --- [수정됨] 문서 인덱싱 함수 (한국어 청크 직접 임베딩) ---
def index_documents(doc_dir):
    print(f"\n--- '{doc_dir}' 내 .md 파일 벡터 인덱싱 시작 (다국어 SBERT, ChromaDB) ---")
    doc_paths = get_document_paths(doc_dir)
    if not doc_paths:
        print("인덱싱할 .md 파일이 없습니다.")
        return

    collection = initialize_chromadb()
    if not collection:
        print("[오류] ChromaDB 컬렉션을 초기화할 수 없어 인덱싱을 중단합니다.")
        return
    
    total_files = len(doc_paths)
    indexed_file_count = 0
    skipped_file_count = 0 # ID 기준 스킵
    error_file_count = 0
    total_chunks_processed = 0

    for file_idx, filepath in enumerate(doc_paths, 1):
        filepath_str = str(filepath)
        print(f"\n   ({file_idx}/{total_files}) 파일 처리 중: {filepath.name}")

        content_ko = read_document_content(filepath)
        if content_ko is None or not content_ko.strip():
            print(f"     - 내용을 읽을 수 없거나 비어있어 건너<0xEB><0x84>니다.")
            error_file_count += 1
            continue

        text_chunks_ko = chunk_text_by_sentences(content_ko, sentences_per_chunk=7)
        if not text_chunks_ko:
            print(f"     - 텍스트 청킹 결과가 없어 건너<0xEB><0x84>니다.")
            error_file_count += 1
            continue
        
        print(f"     - 원본 한국어 문서 청크 수: {len(text_chunks_ko)}")

        chunk_embeddings = []
        chunk_metadatas = []
        chunk_ids = []
        processed_chunks_for_this_file = 0

        for chunk_idx, chunk_ko in enumerate(text_chunks_ko):
            chunk_id_str = f"{filepath_str}_chunk_{chunk_idx}"

            existing_entry = collection.get(ids=[chunk_id_str])
            if existing_entry and existing_entry['ids'] and chunk_id_str in existing_entry['ids']:
                # print(f"       - 청크 ID '{chunk_id_str}'는 이미 DB에 존재하여 건너<0xEB><0x84>니다.")
                if chunk_idx == 0 and len(text_chunks_ko) > 0 : # 첫 청크가 스킵되면 파일 스킵으로 간주
                     is_new_file_to_skip = True
                     for i in range(len(text_chunks_ko)): # 해당 파일의 모든 청크가 존재하는지 확인
                         temp_id = f"{filepath_str}_chunk_{i}"
                         temp_entry = collection.get(ids=[temp_id])
                         if not (temp_entry and temp_entry['ids'] and temp_id in temp_entry['ids']):
                             is_new_file_to_skip = False
                             break
                     if is_new_file_to_skip:
                         skipped_file_count +=1
                continue # 개별 청크 스킵


            # chunk_en = translate_text(chunk_ko, 'ko', 'en') # 번역 삭제
            # if chunk_en.startswith("Error:") or not chunk_en.strip() : # 번역 삭제
            #     print(f"       - 청크 {chunk_idx + 1} 번역 실패. 이 청크는 건너<0xEB><0x84>니다.") # 번역 삭제
            #     continue # 번역 삭제
            
            # 한국어 청크 직접 임베딩
            embedding = get_embedding_for_text(chunk_ko) # 함수명 변경, 한국어 텍스트 직접 전달
            if embedding is None:
                print(f"       - 청크 {chunk_idx + 1} 임베딩 생성 실패. 이 청크는 건너<0xEB><0x84>니다.")
                continue

            chunk_embeddings.append(embedding)
            chunk_metadatas.append({
                "source_filepath": filepath_str,
                "filename": filepath.name,
                "chunk_id_in_doc": chunk_idx,
                "original_text_ko": chunk_ko, # 원본 한국어 청크만 저장
                # "translated_text_en": chunk_en # 삭제
            })
            # documents 파라미터에는 ChromaDB에 저장할 텍스트 자체를 전달. 여기서는 original_text_ko.
            # 임베딩은 embeddings 파라미터로 전달.
            chunk_ids.append(chunk_id_str)
            processed_chunks_for_this_file += 1
            total_chunks_processed +=1

            if len(chunk_ids) >= 50:
                try:
                    # collection.add 시 documents 파라미터 추가 (검색 결과에서 텍스트 바로 확인용)
                    collection.add(embeddings=chunk_embeddings, metadatas=chunk_metadatas, ids=chunk_ids, documents=[m['original_text_ko'] for m in chunk_metadatas])
                    print(f"       - {len(chunk_ids)}개 청크 묶음 DB에 추가 완료.")
                    chunk_embeddings, chunk_metadatas, chunk_ids = [], [], []
                except Exception as db_e:
                    print(f"       - 다수 청크 DB 추가 중 오류: {db_e}")
        
        if chunk_ids: # 남은 청크 저장
            try:
                collection.add(embeddings=chunk_embeddings, metadatas=chunk_metadatas, ids=chunk_ids, documents=[m['original_text_ko'] for m in chunk_metadatas])
                print(f"       - 남은 {len(chunk_ids)}개 청크 DB에 추가 완료.")
            except Exception as db_e:
                print(f"       - 파일 마지막 청크 DB 추가 중 오류: {db_e}")
        
        if processed_chunks_for_this_file > 0:
            indexed_file_count +=1
            print(f"     - 파일 '{filepath.name}'에서 {processed_chunks_for_this_file}개 청크 처리 완료.")
        elif not any(collection.get(ids=[f"{filepath_str}_chunk_{i}"])['ids'] for i in range(len(text_chunks_ko))):
             error_file_count +=1
             print(f"     - 파일 '{filepath.name}' 처리 중 유효한 청크를 DB에 저장하지 못했습니다.")


    print(f"\n--- 벡터 인덱싱 완료 ---")
    print(f"  처리 시도한 총 파일 수: {total_files}")
    print(f"  성공적으로 일부라도 인덱싱된 파일 수: {indexed_file_count}")
    print(f"  건너뛴 파일 수 (모든 청크가 이미 존재 시): {skipped_file_count}")
    print(f"  오류 발생 파일 수: {error_file_count}")
    print(f"  DB에 추가/확인된 총 청크 수 (현재 DB): {collection.count()} (이번 실행에서 신규 처리: {total_chunks_processed})")


# --- [수정됨] 벡터 기반 관련 문서 검색 함수 (한국어 쿼리, 한국어 컨텍스트) ---
def find_related_documents_by_vector_similarity(query_ko, top_n=3):
    print(f"\n--- 벡터 기반 관련 문서 검색 시작 (쿼리: '{query_ko[:30]}...') ---")
    
    collection = initialize_chromadb()
    if not collection:
        print("[오류] ChromaDB 컬렉션을 초기화할 수 없어 검색을 중단합니다.")
        return []

    if not query_ko or not query_ko.strip():
        print("[오류] 검색 쿼리가 비어있습니다.")
        return []

    # query_en = translate_text(query_ko, 'ko', 'en') # 번역 삭제
    # if query_en.startswith("Error:") or not query_en.strip(): # 번역 삭제
    #     print(f"[오류] 쿼리 번역 실패: {query_en}") # 번역 삭제
    #     return [] # 번역 삭제
    # print(f"  번역된 영어 쿼리: '{query_en[:50]}...'") # 번역 삭제

    # 한국어 쿼리 직접 임베딩
    query_embedding = get_embedding_for_text(query_ko) # 함수명 변경, 한국어 쿼리 전달
    if query_embedding is None:
        print("[오류] 쿼리 임베딩 생성에 실패했습니다.")
        return []

    try:
        # collection.add 시 documents를 저장했으므로, include에 "documents" 추가
        results = collection.query(
            query_embeddings=[query_embedding],
            n_results=top_n,
            include=["metadatas", "documents", "distances"] # "documents"는 저장된 원본 청크 (한국어)
        )
    except Exception as e:
        print(f"[오류] 벡터 DB 검색 중 오류 발생: {e}")
        traceback.print_exc()
        return []

    if not results or not results.get('ids') or not results.get('ids')[0]:
        print("[정보] 유사한 문서를 찾지 못했습니다.")
        return []
    
    retrieved_contexts = []
    ids = results.get('ids')[0]
    metadatas = results.get('metadatas')[0]
    documents_retrieved = results.get('documents')[0] if results.get('documents') else [None] * len(ids)
    distances = results.get('distances')[0]

    print(f"상위 {len(ids)}개 관련 문서 청크 정보 (벡터 유사도 기준):")
    for i in range(len(ids)):
        meta = metadatas[i]
        retrieved_doc_text = documents_retrieved[i] if documents_retrieved[i] else meta.get('original_text_ko', '') # documents 우선 사용
        filename = meta.get('filename', 'N/A')
        distance = distances[i]

        print(f"  - {filename} (Distance: {distance:.4f})")
        # print(f"     한국어 컨텍스트: {retrieved_doc_text[:100]}...") # 너무 길면 생략

        # LLM 컨텍스트로는 검색된 한국어 청크를 사용
        retrieved_contexts.append({
            "filepath": meta.get('source_filepath', 'N/A'),
            "filename": filename,
            "context_text_ko": retrieved_doc_text, # 컨텍스트로 사용할 한국어 텍스트
            "score": 1 - distance 
        })
    
    retrieved_contexts.sort(key=lambda x: x["score"], reverse=True)
    return retrieved_contexts


# --- 메인 함수 ---
def main():
    try:
        get_sbert_model()
        initialize_chromadb()
    except SystemExit as e:
        print(f"초기화 실패로 프로그램을 종료합니다: {e}")
        return
    except Exception as e:
        print(f"초기화 중 예기치 않은 오류 발생: {e}")
        traceback.print_exc()
        return

    model_to_use = DEFAULT_GEMINI_MODEL # LLM 모델

    task_mapping = {
        '1': 'summarize', '2': 'memo', '3': 'keyword', '4': 'chat',
        '5': 'comparison',
        '6': 'index', 
        '7': 'related_task_vector_rag',
    }
    # ... (기존 로그/문서 디렉토리 생성 로직 유지)

    while True:
        print("\n" + "="*10 + " 작업 선택 (Gemini API 사용) " + "="*10)
        print("1. 요약 (Summarize) [단일 텍스트, 최적화]")
        print("2. 메모 (Memo) [단일 텍스트, 최적화]")
        print("3. 키워드 추출 (Keyword) [단일 텍스트 대상, 결과 로깅]")
        print("4. 일반 대화 (Chat)")
        print("5. 키워드 로그 비교 (Comparison) [3번 작업 결과 활용]")
        print("--- 문서 관리 & RAG ---")
        print(f"6. 문서 벡터 인덱싱 (index) ['{DOC_DIR}' 내 .md -> 한국어 SBERT 임베딩 -> ChromaDB 저장]")
        print(f"7. 주제 관련 작업 (RAG) [벡터 DB 검색 기반, 한국어 컨텍스트 활용]")
        print("exit: 종료")
        print("="*42) # 길이 조정

        choice = input("선택: ").lower().strip()
        if choice == 'exit':
            break

        task_name = "unknown"
        result = "오류: 처리되지 않음"
        log_this_interaction = True
        user_input_for_log = ""
        log_metadata = {}

        try:
            if choice == '5': # Comparison
                task_name = "comparison"
                comparison_output = perform_comparison_task(model=model_to_use)
                print("\n" + "="*30); print(f"결과 ({task_name}):"); print(comparison_output); print("="*30 + "\n")
                log_this_interaction = False

            elif choice == '6': # Index
                task_name = "index_vector_db"
                index_documents(DOC_DIR)
                log_this_interaction = False

            elif choice == '7': # RAG Task
                task_name = task_mapping[choice]
                user_query_ko = input("질문 또는 정리할 주제를 입력하세요 (한국어): ")
                if not user_query_ko.strip():
                    print("[알림] 입력이 비어 있습니다.")
                    log_this_interaction = False
                    continue
                user_input_for_log = user_query_ko

                related_contexts_info = find_related_documents_by_vector_similarity(user_query_ko, top_n=3)

                if not related_contexts_info:
                    print("[알림] 관련 문서를 찾지 못했습니다. 일반 Chat 방식으로 Fallback 합니다.")
                    task_name = "chat_fallback_after_rag_fail"
                    # fallback_prompt_en = translate_text(user_query_ko, 'ko', 'en') # 삭제
                    # if fallback_prompt_en.startswith("Error"): # 삭제
                    #     result = f"Fallback 프롬프트 번역 실패: {fallback_prompt_en}" # 삭제
                    #     raise Exception(result) # 삭제
                    result = execute_gemini_task(user_query_ko, model=model_to_use) # 직접 한국어 쿼리 전달
                else:
                    print("--- 관련 정보 기반 응답 생성 중 ---")
                    augmented_context_ko_str = "" # 한국어 컨텍스트
                    retrieved_sources_for_log = []
                    for i, ctx_info in enumerate(related_contexts_info):
                        augmented_context_ko_str += f"\n--- 관련 한국어 컨텍스트 {i+1} (출처: {ctx_info['filename']}) ---\n"
                        augmented_context_ko_str += ctx_info['context_text_ko'] + "\n"
                        retrieved_sources_for_log.append({
                            "filename": ctx_info['filename'],
                            "retrieved_korean_chunk_preview": ctx_info['context_text_ko'][:300] + "...", # 한국어 청크
                            "score": ctx_info['score']
                        })
                    log_metadata['retrieved_contexts'] = retrieved_sources_for_log

                    # user_query_en = translate_text(user_query_ko, 'ko', 'en') # 삭제
                    # if user_query_en.startswith("Error:"): # 삭제
                    #     result = f"사용자 질문 영어 번역 실패: {user_query_en}" # 삭제
                    #     raise Exception(result) # 삭제

                    # 최종 한국어 프롬프트 구성: 한국어 질문 + 한국어 컨텍스트 + 한국어 지시
                    # (프롬프트 엔지니어링에 따라 영어로 질문 + 한국어 컨텍스트 + 영어 지시도 가능)
                    # 여기서는 일관되게 한국어 사용
                    final_rag_prompt_ko = f"""다음 질문에 답해주세요: "{user_query_ko}"

아래 제공된 한국어 컨텍스트 정보를 사용하세요:
{augmented_context_ko_str}

위 컨텍스트를 바탕으로 질문에 대한 답변을 한국어로 생성해주세요. 만약 컨텍스트에 답이 없다면, 없다고 명시해주세요.
"""
                    
                    print(f"  Gemini에 전달될 프롬프트 (일부): {final_rag_prompt_ko[:300]}...")
                    result = execute_gemini_task(final_rag_prompt_ko, model=model_to_use)

            elif choice in ('1', '2', '3', '4'): # 기존 단일 입력 작업
                user_input_ko_single = input("작업할 텍스트 또는 질문을 입력하세요 (한국어): ")
                if not user_input_ko_single.strip():
                    print("[알림] 입력이 비어 있습니다.")
                    log_this_interaction = False
                    continue
                user_input_for_log = user_input_ko_single

                if choice not in task_mapping:
                    print("[오류] 내부 오류: task_mapping에 해당 선택지가 없습니다.")
                    log_this_interaction = False
                    continue
                task_name = task_mapping[choice]
                print(f"\n[{task_name}] 작업을 Gemini({model_to_use})에게 요청합니다...")

                if choice == '4': # Chat
                    # english_prompt = translate_text(user_input_for_log, 'auto', 'en') # 삭제
                    # if english_prompt.startswith("Error"): raise Exception(english_prompt) # 삭제
                    result = execute_gemini_task(user_input_for_log, model=model_to_use) # 직접 한국어 입력

                elif choice in ('1', '2'): # Summarize, Memo (Adaptive)
                    result = execute_adaptive_gemini_task(user_input_for_log, task_name, model=model_to_use)
                
                elif choice == '3': # Keyword
                    # user_input_en_for_kw = translate_text(user_input_for_log, 'ko', 'en') # 삭제
                    # if user_input_en_for_kw.startswith("Error"): # 삭제
                    #     raise Exception(f"키워드 추출용 입력 번역 실패: {user_input_en_for_kw}") # 삭제
                    
                    keyword_prompt_template_ko = task_prompts[task_name] # 한국어 키워드 프롬프트
                    korean_prompt_for_kw = keyword_prompt_template_ko.replace("[TEXT]", user_input_for_log) # 한국어 텍스트 삽입
                    
                    keyword_result_ko = query_gemini(korean_prompt_for_kw, model_name=model_to_use) # Gemini는 한국어 키워드 생성 가능

                    # Gemini가 프롬프트 지침에 따라 "키워드: 점수" 형태로 잘 생성한다고 가정
                    # 별도의 번역이나 추가 처리 불필요
                    result = keyword_result_ko
                    # if keyword_result_en.startswith("Error"): # query_gemini가 처리
                    #     result = keyword_result_en
                    # else:
                        # keyword_result_ko = translate_text(keyword_result_en, "en", "ko") # 삭제
                        # result = keyword_result_ko if not keyword_result_ko.startswith("Error") else f"[en_keywords_with_error_in_ko_translation] {keyword_result_en}" # 삭제
                        # log_metadata['original_english_keywords'] = keyword_result_en # 삭제 (Gemini가 한국어 키워드를 줄 것이므로)

            else:
                print("[오류] 잘못된 선택입니다. 메뉴에 있는 번호나 'exit'를 입력해주세요.")
                log_this_interaction = False
                task_name = "invalid_choice"

            if task_name not in ["unknown", "invalid_choice", "index_vector_db"] and choice != '5':
                print("\n" + "="*30)
                print(f"결과 ({task_name}):")
                print(result)
                print("="*30 + "\n")

            if log_this_interaction and isinstance(result, str) and task_name not in ["unknown", "invalid_choice"]:
                log_entry_data = {
                    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    "task": task_name,
                    "input": user_input_for_log,
                    "output": result,
                    "model_used_llm": model_to_use, # Gemini 모델명
                    # "sbert_model_for_rag"는 RAG 작업 시 log_metadata에 추가 가능
                }
                if task_name == 'related_task_vector_rag' or task_name == "index_vector_db": # index는 별도 로그지만, RAG에는 sbert 명시
                    log_entry_data['sbert_model_for_rag'] = SBERT_MODEL_NAME
                if log_metadata:
                    log_entry_data.update(log_metadata)
                
                os.makedirs(LOG_DIR, exist_ok=True)
                with open(LOG_FILENAME, 'a', encoding='utf-8') as f:
                    f.write(json.dumps(log_entry_data, ensure_ascii=False) + '\n')

        except Exception as e:
            print(f"\n[!!! 작업 '{task_name}' 처리 중 주 예외 발생 !!!]")
            print(f"오류 상세: {type(e).__name__} - {e}")
            print("--- Traceback ---")
            traceback.print_exc()
            print("--- End Traceback ---")
            print("다음 작업을 계속 진행합니다.")


if __name__ == "__main__":
    print(f"스크립트 시작: {datetime.datetime.now()}")
    print(f"사용 LLM: Gemini API")
    print(f"기본 Gemini 모델: {DEFAULT_GEMINI_MODEL}")
    print(f"SentenceTransformer 임베딩 모델: {SBERT_MODEL_NAME}")
    print(f"ChromaDB 저장 경로: {CHROMA_DB_PATH}")
    print(f"로그 파일 위치: {LOG_FILENAME}")
    print(f"문서 디렉토리: {DOC_DIR}")

    try:
        os.makedirs(DOC_DIR, exist_ok=True)
        os.makedirs(LOG_DIR, exist_ok=True)
        os.makedirs(CHROMA_DB_PATH, exist_ok=True)
    except OSError as e:
        print(f"[치명적 오류] 필수 디렉토리 생성 불가: {e}. 스크립트를 종료합니다.")
        exit(1)
    
    try:
        main()
    except KeyboardInterrupt:
        print("\n[알림] 사용자에 의해 스크립트가 중단되었습니다.")
    except SystemExit as e:
        print(f"프로그램 종료: {e}")
    except Exception as e:
        print(f"\n[!!! 스크립트 실행 중 치명적인 오류 발생 !!!]")
        print(f"오류 상세: {type(e).__name__} - {e}")
        traceback.print_exc()
    finally:
        print(f"\n스크립트 종료: {datetime.datetime.now()}")

