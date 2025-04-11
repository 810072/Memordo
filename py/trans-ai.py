import json
import datetime
import time
import requests
import os
from googletrans import Translator # googletrans 패키지 설치 필요: pip install googletrans==4.0.0-rc1
from requests.exceptions import RequestException
import httpx # googletrans의 타임아웃 설정을 위해 필요할 수 있음

# --- 상수 정의 ---
OLLAMA_API_URL = "http://localhost:11434/api/generate"  # 사용하는 Ollama API 주소
DEFAULT_OLLAMA_MODEL = "mistral:7b"  # 기본으로 사용할 Ollama 모델
LOG_DIR = "log"  # 로그 파일을 저장할 디렉토리
LOG_FILENAME = os.path.join(LOG_DIR, "interaction_log.jsonl")  # 로그 파일 이름

# --- 번역 함수 ---
def translate_text(text, src_lang, dest_lang, retries=3, delay=1):
    """
    텍스트 번역 함수 (googletrans 사용, 재시도 및 간단한 오류 처리 추가)
    Args:
        text (str): 번역할 텍스트
        src_lang (str): 원본 언어 코드 (예: 'ko')
        dest_lang (str): 대상 언어 코드 (예: 'en')
        retries (int): 실패 시 재시도 횟수
        delay (int): 재시도 간 기본 대기 시간 (초)
    Returns:
        str: 번역된 텍스트 또는 오류 메시지
    """
    if not text: # 빈 텍스트 처리
        return ""

    for attempt in range(retries):
        try:
            # 타임아웃 설정이 필요하면 httpx.Timeout 객체 사용 가능
            # translator = Translator(timeout=httpx.Timeout(10.0))
            translator = Translator()
            translation = translator.translate(text, src=src_lang, dest=dest_lang)

            # 번역 결과가 유효한지 확인
            if translation and hasattr(translation, 'text') and translation.text is not None:
                return translation.text
            else:
                # 예상치 못한 번역 결과 (예: None 반환)
                error_msg = f"Translation returned unexpected result (attempt {attempt+1}/{retries}). Input: '{text[:50]}...', Src: {src_lang}, Dest: {dest_lang}"
                print(f"[Warning] {error_msg}")

        except RequestException as e: # requests 관련 네트워크 오류 (googletrans 내부 포함 가능)
            error_msg = f"Network error during translation (attempt {attempt+1}/{retries}): {type(e).__name__} - {e}"
            print(f"[Warning] {error_msg}")
        except AttributeError as e: # googletrans의 특정 내부 오류 처리 (예: 번역 결과 구조 문제)
             error_msg = f"Attribute error during translation processing (attempt {attempt+1}/{retries}): {e}"
             print(f"[Warning] {error_msg}")
        except Exception as e: # 그 외 예상치 못한 오류 (googletrans 내부 오류 등)
            error_msg = f"Unexpected error during translation (attempt {attempt+1}/{retries}): {type(e).__name__} - {e}"
            print(f"[Warning] {error_msg}")

        if attempt < retries - 1:
            # Exponential backoff: 재시도 시 대기 시간 증가
            current_delay = delay * (2 ** attempt)
            print(f"Retrying translation in {current_delay} seconds...")
            time.sleep(current_delay)
        else:
            # 최종 실패
            return f"Error: Translation failed after {retries} attempts. Input: '{text[:50]}...'"

    # 이 부분은 이론적으로 도달하지 않아야 함
    return f"Error: Translation failed unexpectedly after loop. Input: '{text[:50]}...'"


# --- Ollama 쿼리 함수 ---
def query_ollama(prompt, model=DEFAULT_OLLAMA_MODEL, url=OLLAMA_API_URL):
    """
    Ollama API에 쿼리를 보내고 응답 텍스트를 반환하는 함수
    Args:
        prompt (str): Ollama 모델에 전달할 프롬프트 (영어로 가정)
        model (str): 사용할 Ollama 모델 이름
        url (str): Ollama API 엔드포인트 URL
    Returns:
        str: Ollama 모델의 응답 텍스트 또는 오류 메시지
    """
    headers = {"Content-Type": "application/json"}
    data = {
        "prompt": prompt,
        "model": model,
        "stream": False,  # 스트리밍 응답 비활성화
    }
    try:
        # 요청 타임아웃 설정 (예: 60초)
        response = requests.post(url, headers=headers, data=json.dumps(data), timeout=60)
        response.raise_for_status()  # HTTP 오류 발생 시 예외 발생

        # 응답 JSON 파싱
        json_data = response.json()

        # 응답 구조 확인 및 결과 추출
        if "response" in json_data:
            return json_data["response"].strip() # 앞뒤 공백 제거
        elif "error" in json_data:
             return f"Error: Ollama API returned an error: {json_data['error']}"
        else:
            # 예상치 못한 응답 형식
            return f"Error: 'response' key not found in Ollama API response. Received: {str(json_data)[:200]}..."

    except requests.exceptions.Timeout:
        return f"Error: Request to Ollama timed out."
    except requests.exceptions.RequestException as e:
        return f"Error querying Ollama: Network or connection error - {e}"
    except json.JSONDecodeError as e:
        # 응답이 유효한 JSON이 아닌 경우
        return f"Error decoding Ollama response: {e}. Response text: '{response.text[:100]}...'"
    except Exception as e:
        # 그 외 예상치 못한 오류
        return f"An unexpected error occurred in query_ollama: {type(e).__name__} - {e}"


# --- 작업별 프롬프트 템플릿 ---
task_prompts = {
    # 내용 유형 분석용 프롬프트
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

    # 기본 요약 프롬프트 (Fallback 또는 일반용)
    "summarize": "Please summarize the following text in three concise sentences, capturing the main points:\n[TEXT]",
    # 기본 메모 프롬프트 (Fallback 또는 일반용)
    "memo": "Based on the following content, create bullet points highlighting the key ideas and decisions:\n[TEXT]",

    # 키워드 추출 프롬프트
    "keyword": """Identify about 10 of the most important keywords from the following text. Estimate the importance (relevance) of each keyword to the overall text content as a score between 0 and 1.
List ONLY the top 5 keywords with the highest scores and their corresponding scores in the following format:
keyword1: score1
keyword2: score2
keyword3: score3
keyword4: score4
keyword5: score5

[TEXT]""",

    # 관계성 평가 프롬프트
    "comparison": """Below are two lists of keywords and their importance scores extracted from two different texts. Evaluate the thematic similarity between these two keyword lists and provide a score between 0 (no similarity) and 1 (very high similarity).
Output ONLY the similarity score, rounded to two decimal places.

List 1:
[KEYWORDS1]

List 2:
[KEYWORDS2]"""
}

# --- 내용 유형에 따른 동적 프롬프트 생성 함수 ---
def create_adaptive_prompt(user_input_ko, task_type, content_type):
    """
    내용 유형에 따라 작업 프롬프트를 동적으로 조정하고 영어로 번역합니다.
    Args:
        user_input_ko (str): 사용자의 원본 한국어 입력
        task_type (str): 수행할 작업 유형 ('summarize' 또는 'memo')
        content_type (str): 감지된 내용 유형 (예: 'meeting_notes')
    Returns:
        str: 최종적으로 생성되고 번역된 영어 프롬프트 또는 오류 메시지
    """
    base_prompt_ko = task_prompts[task_type] # 기본 한국어 프롬프트 (이 코드에서는 영어지만 개념 설명상)
    adapted_prompt_ko = base_prompt_ko # 기본값 설정

    # 내용 유형에 따라 프롬프트 구체화 (한국어 기준 예시, 실제로는 영어로 작성됨)
    if task_type == "memo":
        if content_type == "meeting_notes":
            # 회의록 -> 실행 항목, 결정 사항 강조
            adapted_prompt_ko = "Based on the following meeting notes, create clear bullet points for **key discussion points, decisions made, and action items (including responsible persons if mentioned)**:\n[TEXT]"
        elif content_type == "idea_brainstorming":
            # 아이디어 -> 핵심 아이디어, 관련 포인트 정리
            adapted_prompt_ko = "From the following brainstorming content, organize the **core ideas and related key points** into bullet points:\n[TEXT]"
        elif content_type == "todo_list":
            # 할 일 목록 -> 명확하게 재정리
            adapted_prompt_ko = "Reformat the following to-do list into clear and concise bullet points:\n[TEXT]"
        elif content_type == "technical_explanation":
            # 기술 설명 -> 주요 단계, 요소 요약
            adapted_prompt_ko = "From the following technical explanation, create bullet points for the **main steps, components, or key takeaways**:\n[TEXT]"
        # 다른 유형은 기본 메모 프롬프트 사용
        else:
            adapted_prompt_ko = task_prompts["memo"] # 명시적으로 기본 프롬프트 사용

    elif task_type == "summarize":
        if content_type == "technical_explanation":
            # 기술 설명 -> 목적, 방법, 결과 요약
            adapted_prompt_ko = "Summarize the following technical text in three sentences, focusing on the **core purpose, main methodology/process (if any), and significant results or conclusions**:\n[TEXT]"
        elif content_type == "meeting_notes":
            # 회의록 -> 중요 논의 결과, 결정 사항 요약
            adapted_prompt_ko = "Provide a three-sentence summary of the following meeting notes, highlighting the **most important discussion outcomes and decisions**:\n[TEXT]"
        elif content_type == "personal_reflection":
             # 개인 생각 -> 주요 주제, 감정 요약
             adapted_prompt_ko = "Summarize the main themes or feelings expressed in the following personal reflection in three sentences:\n[TEXT]"
        # 다른 유형은 기본 요약 프롬프트 사용
        else:
             adapted_prompt_ko = task_prompts["summarize"] # 명시적으로 기본 프롬프트 사용

    # 최종 프롬프트 생성 (텍스트 삽입 - 사용자의 '영어' 텍스트를 삽입해야 함)
    # 이 단계 전에 user_input_ko를 영어로 번역해야 함.
    user_input_en = translate_text(user_input_ko, "ko", "en")
    if user_input_en.startswith("Error"):
         # 사용자 입력 번역 실패 처리
         raise Exception(f"Failed to translate user input for adaptive prompt: {user_input_en}")

    # 영어 프롬프트 템플릿에 번역된 영어 사용자 입력을 삽입
    final_prompt_en = adapted_prompt_ko.replace("[TEXT]", user_input_en)

    # 이미 영어 프롬프트이므로 별도 번역 필요 없음
    return final_prompt_en


# --- 핵심 실행 로직 함수 (Ollama 호출 및 번역) ---
def execute_ollama_task(english_prompt, model=DEFAULT_OLLAMA_MODEL):
    """
    Ollama에 영어 프롬프트를 보내고, 응답을 한국어로 번역하여 반환합니다.
    Args:
        english_prompt (str): Ollama에 보낼 영어 프롬프트
        model (str): 사용할 Ollama 모델
    Returns:
        str: 최종 한국어 번역 결과 또는 오류 메시지
    """
    # Ollama에 쿼리 (영어 프롬프트 사용)
    ollama_response_en = query_ollama(english_prompt, model=model)
    if ollama_response_en.startswith("Error"):
        # Ollama 쿼리 실패 시 오류 메시지 반환
        return ollama_response_en

    # Ollama 응답을 한국어로 번역
    ollama_response_ko = translate_text(ollama_response_en, "en", "ko")
    # 번역 결과 반환 (성공 또는 번역 오류 메시지)
    return ollama_response_ko


# --- 2단계 실행 함수: 분류 -> 적응형 프롬프트 -> 실행 ---
def execute_adaptive_ollama_task(user_input_ko, task_type, model=DEFAULT_OLLAMA_MODEL):
    """
    내용 유형 분석 후 적응형 프롬프트를 사용하여 Ollama 작업을 수행하고 결과를 반환합니다.
    Args:
        user_input_ko (str): 사용자의 원본 한국어 입력
        task_type (str): 수행할 작업 유형 ('summarize' 또는 'memo')
        model (str): 사용할 Ollama 모델
    Returns:
        str: 최종 한국어 결과 또는 처리 중 발생한 오류 메시지
    """
    content_type = "unknown" # 기본 내용 유형

    # --- 1단계: 내용 유형 분석 ---
    try:
        print("[1단계] 내용 유형 분석 중...")
        # 분류 프롬프트 생성 (한국어 사용자 입력 포함)
        classify_prompt_ko = task_prompts['classify'].replace("[TEXT]", user_input_ko)
        # 분류 프롬프트 번역 (ko -> en)
        classify_prompt_en = translate_text(classify_prompt_ko, "ko", "en")

        if classify_prompt_en.startswith("Error"):
            print(f"  [경고] 내용 분석 프롬프트 번역 실패: {classify_prompt_en}. 기본 프롬프트를 사용합니다.")
            # content_type은 'unknown'으로 유지
        else:
            # Ollama에 내용 분류 요청 (영어 프롬프트 사용)
            classification_result_en = query_ollama(classify_prompt_en, model=model)

            # ===========================================================
            # <<< 여기에 print 문 추가하여 Raw 결과 확인 >>>
            print(f"  [Debug] Raw classification result from Ollama: '{classification_result_en}'")
            # ===========================================================

            # 이제 모델의 Raw 응답을 확인한 후, 기존 로직을 계속 진행합니다.
            if classification_result_en.startswith("Error"):
                 print(f"  [경고] 내용 유형 분석 실패: {classification_result_en}. 기본 프롬프트를 사용합니다.")
                 # content_type은 'unknown'으로 유지
            else:
                # Ollama 응답에서 유형 레이블만 추출 시도 (간단한 처리)
                # 응답이 비어있거나 None일 경우를 대비하여 .strip() 전에 확인
                if classification_result_en and isinstance(classification_result_en, str):
                    detected_type = classification_result_en.strip().lower().split()[0] if classification_result_en.strip() else ""
                else:
                    detected_type = "" # 유효하지 않은 응답 처리

                # 예상된 레이블 목록
                expected_types = ["meeting_notes", "idea_brainstorming", "technical_explanation",
                                  "personal_reflection", "todo_list", "general_information", "other"]

                if detected_type in expected_types:
                    content_type = detected_type
                    # 처리 후 감지된 유형도 명시적으로 출력 (디버깅에 도움)
                    print(f"  감지된 내용 유형 (처리 후): {content_type}")
                elif detected_type: # 예상 목록에는 없지만 뭔가 응답이 온 경우
                     print(f"  [정보] 예상치 못한 내용 유형 응답 '{detected_type}' 감지됨. 'other'로 처리합니다.")
                     content_type = "other"
                else: # 응답이 비어있거나 유효하지 않은 경우
                     print(f"  [경고] 내용 유형 분석 결과가 비어있거나 유효하지 않음. 기본 프롬프트를 사용합니다.")
                     # content_type은 'unknown'으로 유지


    except Exception as e:
        # 분류 단계에서 예외 발생 시
        print(f"  [경고] 내용 유형 분석 중 예외 발생: {type(e).__name__} - {e}. 기본 프롬프트를 사용합니다.")
        # content_type은 'unknown'으로 유지

    # --- 2단계: 적응형 프롬프트 생성 및 실행 ---
    # (이하 코드는 이전과 동일)
    final_result_ko = f"Error: Adaptive task '{task_type}' failed before execution." # 기본 오류 메시지
    try:
        print(f"[2단계] 내용 유형({content_type}) 기반 '{task_type}' 작업 실행 중...")
        # 내용 유형을 기반으로 최종 실행할 영어 프롬프트 생성
        # create_adaptive_prompt 함수는 내부적으로 user_input_ko를 영어로 번역함
        final_english_prompt = create_adaptive_prompt(user_input_ko, task_type, content_type)
        if final_english_prompt.startswith("Error"): # 프롬프트 생성/번역 실패
             raise Exception(f"Adaptive prompt creation failed: {final_english_prompt}")

        # 생성된 최종 영어 프롬프트를 사용하여 Ollama 실행 및 결과 번역
        final_result_ko = execute_ollama_task(final_english_prompt, model=model)
        return final_result_ko

    except Exception as e:
        # 적응형 프롬프트 생성 또는 최종 실행 중 오류 발생 시
        error_msg = f"적응형 작업({task_type}) 처리 중 오류 발생: {type(e).__name__} - {e}."
        print(f"  [오류] {error_msg}")
        print("[Fallback] 기본 프롬프트로 작업 재시도 중...")
        # 오류 발생 시, 안전하게 기본 프롬프트로 다시 시도 (Fallback)
        try:
            # 기본 프롬프트 템플릿 가져오기 (영어)
            default_prompt_template_en = task_prompts[task_type]
            # 사용자 입력 번역 (ko -> en)
            user_input_en = translate_text(user_input_ko, "ko", "en")
            if user_input_en.startswith("Error"):
                 return f"오류: Fallback 시 사용자 입력 번역 실패 - {user_input_en}"

            # 기본 영어 프롬프트 생성
            default_prompt_en = default_prompt_template_en.replace("[TEXT]", user_input_en)

            # 기본 프롬프트로 Ollama 실행 및 결과 번역
            fallback_result = execute_ollama_task(default_prompt_en, model=model)
            return fallback_result # Fallback 결과 반환
        except Exception as fallback_e:
            # Fallback 마저 실패한 경우
            return f"오류: Fallback 작업 실행 중 오류 발생 - {type(fallback_e).__name__} - {fallback_e}"



# --- Comparison 기능 함수 ---
def perform_comparison_task():
    """로그 파일에서 keyword 결과를 보여주고 사용자가 선택한 2개의 유사성 점수를 계산"""
    keyword_logs = []
    try:
        # 로그 파일 읽기
        if not os.path.exists(LOG_FILENAME):
             return "[오류] 로그 파일을 찾을 수 없습니다. 'keyword' 작업을 먼저 수행해주세요."

        with open(LOG_FILENAME, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    log_entry = json.loads(line)
                    # 'keyword' 작업이고, input과 output이 있는지 확인
                    if log_entry.get('task') == 'keyword' and 'output' in log_entry and 'input' in log_entry:
                         # output이 비어있지 않은지 확인 (예: 오류 메시지가 아님)
                         if isinstance(log_entry['output'], str) and not log_entry['output'].startswith("Error:") and ':' in log_entry['output']:
                             keyword_logs.append({
                                 "timestamp": log_entry.get('timestamp', 'N/A'),
                                 # 입력 내용의 일부만 표시
                                 "input_snippet": log_entry['input'][:30] + ('...' if len(log_entry['input']) > 30 else ''),
                                 "output": log_entry['output'] # 키워드 결과 저장
                             })
                except json.JSONDecodeError:
                    print(f"[경고] 로그 파일 '{LOG_FILENAME}'의 {line_num}번째 라인 파싱 실패. 건너<0xEB><0x84>니다.")
                    continue
                except Exception as e: # 다른 예외 처리 (예: 키 접근 오류)
                    print(f"[경고] 로그 파일 '{LOG_FILENAME}'의 {line_num}번째 라인 처리 중 오류: {type(e).__name__}")
                    continue


    except FileNotFoundError: # 위에서 처리했지만 혹시 모를 경우 대비
        return "[오류] 로그 파일을 찾을 수 없습니다. 'keyword' 작업을 먼저 수행해주세요."
    except Exception as e:
        return f"[오류] 로그 파일 읽기 중 오류 발생: {e}"


    if len(keyword_logs) < 2:
        return f"[오류] 비교할 유효한 'keyword' 작업 결과가 로그에 2개 이상 필요합니다. 현재 {len(keyword_logs)}개 있습니다."

    # --- 사용자에게 목록 보여주기 ---
    print("\n--- 비교 가능한 '키워드 추출' 로그 목록 ---")
    for i, log_data in enumerate(keyword_logs):
        # 로그 항목 번호, 타임스탬프, 입력 내용 일부 표시
        print(f"{i+1}. [{log_data['timestamp']}] Input: \"{log_data['input_snippet']}\"")
    print("-----------------------------------------")

    # --- 사용자로부터 두 개의 로그 번호 입력받기 ---
    selected_indices = []
    while len(selected_indices) < 2:
        try:
            if not selected_indices: # 첫 번째 번호 요청
                 prompt_msg = f"비교할 첫 번째 로그 번호 (1-{len(keyword_logs)})를 입력하세요: "
            else: # 두 번째 번호 요청
                 prompt_msg = f"비교할 두 번째 로그 번호 (1-{len(keyword_logs)}, 첫 번째와 달라야 함)를 입력하세요: "

            choice_str = input(prompt_msg).strip()
            if not choice_str: continue # 빈 입력 무시

            choice_num = int(choice_str)
            selected_index = choice_num - 1 # 실제 리스트 인덱스로 변환

            if 0 <= selected_index < len(keyword_logs):
                if selected_index not in selected_indices:
                    selected_indices.append(selected_index)
                else:
                    print("[오류] 이미 선택한 로그 번호입니다. 다른 번호를 입력해주세요.")
            else:
                print(f"[오류] 1에서 {len(keyword_logs)} 사이의 번호를 입력해주세요.")

        except ValueError:
            print("[오류] 유효한 숫자를 입력해주세요.")
        except EOFError: # Ctrl+D 등으로 입력 종료 시
             print("\n입력이 중단되었습니다.")
             return "[알림] 사용자 입력 중단됨."

    # 선택된 로그 정보 가져오기
    log1 = keyword_logs[selected_indices[0]]
    log2 = keyword_logs[selected_indices[1]]

    keywords1_str = log1['output'] # 키워드 목록 문자열
    keywords2_str = log2['output'] # 키워드 목록 문자열
    timestamp1 = log1.get('timestamp', 'N/A')
    timestamp2 = log2.get('timestamp', 'N/A')

    print(f"\n--- 선택된 비교 대상 ---")
    print(f"1: [{timestamp1}] Input: \"{log1['input_snippet']}\"")
    # print(f"   Keywords 1:\n{keywords1_str}") # 필요 시 키워드 내용도 출력
    print(f"2: [{timestamp2}] Input: \"{log2['input_snippet']}\"")
    # print(f"   Keywords 2:\n{keywords2_str}")
    print("-------------------------")

    # --- Ollama 비교 요청 ---
    try:
        # 비교 프롬프트 생성 (한국어)
        comparison_prompt_ko = task_prompts["comparison"]
        comparison_prompt_ko = comparison_prompt_ko.replace("[KEYWORDS1]", keywords1_str)
        comparison_prompt_ko = comparison_prompt_ko.replace("[KEYWORDS2]", keywords2_str)

        # 프롬프트 번역 (ko -> en)
        comparison_prompt_en = translate_text(comparison_prompt_ko, "ko", "en")
        if comparison_prompt_en.startswith("Error"):
            raise Exception(f"Comparison 프롬프트 번역 실패: {comparison_prompt_en}")

        print(f"\n[comparison] 작업을 Ollama({DEFAULT_OLLAMA_MODEL})에게 요청합니다...")
        # Ollama 작업 실행 및 결과 번역 (en -> ko)
        # 유사성 점수 자체는 숫자이므로 번역이 큰 의미 없을 수 있으나, 만약 Ollama가 텍스트 설명을 추가한다면 번역 필요
        comparison_result_ko = execute_ollama_task(comparison_prompt_en, model=DEFAULT_OLLAMA_MODEL)
        if comparison_result_ko.startswith("Error"):
             return f"[오류] 유사성 평가 중 오류 발생: {comparison_result_ko}"

        # 결과에서 숫자 점수만 추출 시도
        try:
             # 쉼표를 점으로 바꾸고, 앞뒤 공백 제거 후 float 변환 시도
             score_text = comparison_result_ko.strip().replace(',', '.')
             # 결과에 숫자 외 다른 텍스트가 포함될 수 있으므로, 숫자 부분만 찾기 시도 (더 복잡한 정규식 사용 가능)
             potential_score = ''.join(c for c in score_text if c.isdigit() or c == '.')
             if potential_score:
                 score = float(potential_score)
                 # 점수 범위 확인 (0~1) - 선택적
                 if 0 <= score <= 1:
                      return f"선택된 두 로그 간의 유사성 점수: {score:.2f}"
                 else:
                      return f"계산된 유사성 점수 ({score:.2f})가 범위를 벗어났습니다. 원본 결과: {comparison_result_ko}"
             else:
                  # 숫자 변환 실패 시 원본 텍스트 결과 반환
                 return f"유사성 평가 결과 (텍스트): {comparison_result_ko}"
        except ValueError:
             # float 변환 실패 시 원본 텍스트 결과 반환
             return f"유사성 평가 결과 (텍스트, 점수 변환 불가): {comparison_result_ko}"

    except Exception as e:
        return f"[오류] Comparison 작업 처리 중 문제 발생: {type(e).__name__} - {e}"


# --- 메인 함수 ---
def main():
    """메인 함수: 사용자 입력, 작업 선택, Ollama 쿼리 (필요시 적응형), 결과 출력 및 로깅"""
    model_to_use = DEFAULT_OLLAMA_MODEL  # 사용할 모델 설정

    # 작업 번호와 task_type 매핑
    task_mapping = {
        '1': 'summarize',
        '2': 'memo',
        '3': 'keyword',
        # '4'는 chat으로 별도 처리
        '5': 'comparison' # comparison은 perform_comparison_task 함수에서 처리
    }

    # 로그 디렉토리 생성 시도
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
    except OSError as e:
        print(f"[오류] 로그 디렉토리 '{LOG_DIR}' 생성 실패: {e}")
        return # 디렉토리 생성 못하면 종료

    # 메인 루프 시작
    while True:
        print("\n" + "="*10 + " 작업 선택 " + "="*10)
        print("1. 요약 (Summarize) [내용 분석 후 최적화 시도]")
        print("2. 메모 (Memo) [내용 분석 후 최적화 시도]")
        print("3. 키워드 추출 (Keyword)")
        print("4. 일반 대화 (Chat)")
        print("5. 관계성 평가 (Comparison) [로그 선택 방식]")
        print("exit: 종료")
        print("="*32)

        choice = input("선택: ").lower().strip() # 입력 받고 소문자로 변환, 앞뒤 공백 제거
        if choice == 'exit':
            break # 루프 종료

        if choice == '5': # Comparison 작업
            # comparison 작업 수행 함수 호출
            comparison_output = perform_comparison_task()
            print("\n" + "="*30)
            print(f"결과 (comparison):")
            print(comparison_output)
            print("="*30 + "\n")
            # Comparison 결과는 별도 로깅 안 함 (사용자가 선택한 로그 기반이므로)

        elif choice in ('1', '2', '3', '4'): # 단일 입력 작업 또는 채팅
            user_input_ko = input("작업할 텍스트 또는 질문을 입력하세요: ")
            if not user_input_ko.strip(): # 입력이 비어있는지 확인
                print("[알림] 입력이 비어 있습니다. 다시 입력해주세요.")
                continue # 다음 루프 반복

            task_name = "알 수 없는 작업" # 기본값
            result = "오류: 처리되지 않음" # 기본 결과값

            try:
                if choice == '4': # 일반 대화 (Chat)
                    task_name = "chat"
                    print(f"\n[{task_name}] 작업을 Ollama({model_to_use})에게 요청합니다...")
                    # 1. 사용자 입력 번역 (ko -> en)
                    english_prompt = translate_text(user_input_ko, 'ko', 'en')
                    if english_prompt.startswith("Error"):
                         # 번역 실패 시 예외 발생시켜 아래 catch 블록에서 처리
                         raise Exception(f"일반 대화 입력 번역 실패: {english_prompt}")
                    # 2. Ollama 작업 실행 및 결과 번역 (en -> ko)
                    result = execute_ollama_task(english_prompt, model=model_to_use)

                elif choice in ('1', '2'): # 요약(Summarize) 또는 메모(Memo) - 적응형 로직 사용
                    task_type = task_mapping[choice]
                    task_name = task_type
                    print(f"\n[{task_name}] 작업을 Ollama({model_to_use})에게 (적응형으로) 요청합니다...")
                    # 2단계 실행 함수 호출 (내부적으로 분류, 프롬프트 생성, 실행, 번역 모두 처리)
                    result = execute_adaptive_ollama_task(user_input_ko, task_type, model=model_to_use)

                elif choice == '3': # 키워드 추출 (Keyword) - 기존 방식 유지
                    task_type = task_mapping[choice]
                    task_name = task_type
                    print(f"\n[{task_name}] 작업을 Ollama({model_to_use})에게 요청합니다...")
                    # 1. 키워드 추출용 프롬프트 생성 (한국어 기반 -> 영어 번역)
                    keyword_prompt_ko = task_prompts[task_type].replace("[TEXT]", user_input_ko)
                    english_prompt = translate_text(keyword_prompt_ko, "ko", "en")
                    if english_prompt.startswith("Error"):
                         raise Exception(f"'{task_name}' 프롬프트 번역 실패: {english_prompt}")
                    # 2. Ollama 작업 실행 및 결과 번역 (en -> ko)
                    result = execute_ollama_task(english_prompt, model=model_to_use)

                else:
                    # 이 경우는 발생하면 안 되지만 방어적으로 추가
                    print(f"오류: 내부 로직 오류. 선택({choice}) 처리 불가.")
                    continue # 다음 루프로

                # --- 결과 출력 ---
                print("\n" + "="*30)
                print(f"결과 ({task_name}):")
                print(result) # 최종 결과 (한국어) 출력
                print("="*30 + "\n")

                # --- 로깅 (오류가 아닐 경우) ---
                # 결과가 문자열이고 "Error:"로 시작하지 않는 경우에만 로깅
                if isinstance(result, str) and not result.startswith("Error:"):
                    try:
                        # 로그 항목 구성
                        log_entry = {
                            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(), # UTC 시간 기록
                            "task": task_name,
                            "input": user_input_ko, # 원본 한국어 입력
                            "output": result # 최종 한국어 결과
                            # 필요 시 "model_used": model_to_use 등 추가 정보 로깅 가능
                        }
                        # 로그 디렉토리 다시 한번 확인 (혹시 삭제되었을 경우 대비)
                        os.makedirs(LOG_DIR, exist_ok=True)
                        # 로그 파일에 JSONL 형식으로 추가 (append mode)
                        with open(LOG_FILENAME, 'a', encoding='utf-8') as f:
                            # ensure_ascii=False로 한국어 깨짐 방지
                            f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')
                    except Exception as log_e:
                        # 로깅 중 오류 발생 시 경고 출력
                        print(f"[오류] 로그 파일 '{LOG_FILENAME}'에 저장 중 문제 발생: {log_e}")

            except Exception as e:
                 # 각 작업(choice) 처리 중 발생한 예외 (예: 번역 실패, Ollama 통신 실패 등)
                print(f"\n[!!! 오류 발생 !!!]")
                print(f"작업 '{task_name}' 처리 중 오류: {type(e).__name__} - {e}")
                print("다음 작업을 계속 진행합니다.")
                # 오류가 발생했으므로, 'result' 변수에는 오류 메시지가 있거나 기본 오류값이 있을 것임.
                # 로깅은 위에서 오류가 아닐 경우에만 하므로 여기서는 추가 로깅 불필요.

        else: # 잘못된 선택 (1, 2, 3, 4, 5, exit 외)
            print("[오류] 잘못된 선택입니다. 메뉴에 있는 번호나 'exit'를 입력해주세요.")

# --- 스크립트 실행 시작점 ---
if __name__ == "__main__":
    print(f"스크립트 시작: {datetime.datetime.now()}")
    print(f"사용 모델: {DEFAULT_OLLAMA_MODEL}")
    print(f"Ollama API URL: {OLLAMA_API_URL}")
    print(f"로그 파일 위치: {LOG_FILENAME}")
    try:
        main() # 메인 함수 실행
    except KeyboardInterrupt:
         print("\n[알림] 사용자에 의해 스크립트가 중단되었습니다.")
    finally:
        # 스크립트 종료 시 메시지 출력
        print(f"\n스크립트 종료: {datetime.datetime.now()}")

