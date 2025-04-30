import json
import datetime
import time
import requests
import os
from pathlib import Path
from googletrans import Translator, LANGUAGES # googletrans 패키지 설치 필요: pip install googletrans==4.0.0-rc1
from requests.exceptions import RequestException
import httpx # googletrans의 타임아웃 설정을 위해 필요할 수 있음
import traceback # 상세 오류 로깅용
import re # 점수 추출 등 필요

# --- 상수 정의 ---
OLLAMA_API_URL = "http://localhost:11434/api/generate"
DEFAULT_OLLAMA_MODEL = "mistral:7b"
# 경로 설정 (스크립트 위치 기준 상대 경로 또는 필요시 절대 경로 사용)
BASE_DIR = os.path.dirname(os.path.abspath(__file__)) # 스크립트가 있는 디렉토리
DOC_DIR = os.path.join(BASE_DIR, "Doc")      # 문서 디렉토리
LOG_DIR = os.path.join(BASE_DIR, "log")      # 로그 디렉토리
# 절대 경로 예시:
# DOC_DIR = "/Doc"
# LOG_DIR = "/log"

LOG_FILENAME = os.path.join(LOG_DIR, "interaction_log.jsonl")

# --- 번역 함수 (오류 처리 강화 및 언어 감지 추가) ---
def detect_language(text):
    """텍스트의 언어를 감지하는 함수"""
    if not text or not isinstance(text, str) or not text.strip():
        return None
    try:
        # 매번 새로 생성하여 상태 문제 방지 시도
        translator = Translator()
        detected = translator.detect(text)
        # print(f"[Debug] Detected language: {detected.lang} (confidence: {detected.confidence}) for text: '{text[:50]}...'")
        return detected.lang
    except Exception as e:
        print(f"[Warning] Language detection failed: {e}")
        # 언어 감지 API는 불안정할 수 있으므로, 실패 시 None 반환이 중요
        return None # 감지 실패 시 None 반환

def translate_text(text, src_lang, dest_lang, retries=3, delay=1):
    """텍스트 번역 함수 (언어 감지 기반 소스 언어 지정 가능)"""
    if not text or not isinstance(text, str) or not text.strip():
        # print(f"[Debug] Skipping translation for empty or invalid input: {text}")
        return ""

    # 소스 언어가 'auto' 또는 None이면 감지 시도
    source_language = src_lang
    if source_language is None or str(source_language).lower() == 'auto':
        detected_src = detect_language(text)
        # 감지된 언어가 LANGUAGES 목록에 있는지 확인 (googletrans가 지원하는지)
        if detected_src and detected_src in LANGUAGES:
            source_language = detected_src
            # print(f"[Debug] Auto-detected source language: {source_language}")
        else:
            # 감지 실패 또는 미지원 언어 시 기본값 설정
            # 보통 한국어->영어, 영어->한국어 변환이 많으므로 추정
            source_language = 'ko' if dest_lang == 'en' else 'en'
            print(f"[Warning] Language detection failed or unsupported ('{detected_src}'), assuming source is '{source_language}' for target '{dest_lang}'")

    # 목적 언어가 유효한지 확인 (선택적)
    if dest_lang not in LANGUAGES:
        error_msg = f"Error: Invalid destination language code: {dest_lang}"
        print(f"[Error] {error_msg}")
        return error_msg

    # 소스 언어와 목적 언어가 같으면 번역 불필요
    if source_language == dest_lang:
        # print(f"[Debug] Source and destination languages are the same ({source_language}), skipping translation.")
        return text

    translator = Translator() # 매번 새로 생성 시도
    for attempt in range(retries):
        try:
            # 타임아웃 설정 필요 시 httpx 사용 (주석 처리)
            # translator = Translator(timeout=httpx.Timeout(10.0))
            translation = translator.translate(text, src=source_language, dest=dest_lang)

            if translation and hasattr(translation, 'text') and translation.text is not None:
                # print(f"[Debug] Translation successful: '{text[:30]}...' -> '{translation.text[:30]}...'")
                return translation.text
            else:
                # None 또는 예상치 못한 결과 처리
                error_msg = f"Translation returned unexpected result (attempt {attempt+1}/{retries}). Input: '{text[:50]}...', Src: {source_language}, Dest: {dest_lang}, Result: {translation}"
                print(f"[Warning] {error_msg}")

        # requests 및 httpx 관련 네트워크 오류 명시적 처리
        except (RequestException, httpx.RequestError) as e:
            error_msg = f"Network error during translation (attempt {attempt+1}/{retries}): {type(e).__name__} - {e}"
            print(f"[Warning] {error_msg}")
        # googletrans 라이브러리 내부 오류 가능성 처리 (예: AttributeError)
        except AttributeError as e:
             error_msg = f"Attribute error during translation processing (attempt {attempt+1}/{retries}): {e}"
             print(f"[Warning] {error_msg}")
        # 그 외 모든 예외 처리
        except Exception as e:
            error_msg = f"Unexpected error during translation (attempt {attempt+1}/{retries}): {type(e).__name__} - {e}"
            print(f"[Warning] {error_msg}")
            # 상세 디버깅 필요시 주석 해제
            # traceback.print_exc()

        # 재시도 로직
        if attempt < retries - 1:
            current_delay = delay * (2 ** attempt) # Exponential backoff
            print(f"Retrying translation in {current_delay} seconds...")
            time.sleep(current_delay)
        else:
            # 최종 실패
            final_error = f"Error: Translation failed after {retries} attempts. Input: '{text[:50]}...', Src: {source_language}, Dest: {dest_lang}"
            print(f"[Error] {final_error}")
            return final_error # 최종 실패 시 오류 메시지 반환

    # 루프를 모두 돌았는데도 반환되지 않은 경우 (이론상 도달 불가)
    return f"Error: Translation failed unexpectedly after loop. Input: '{text[:50]}...'"


# --- Ollama 쿼리 함수 (타임아웃 증가 유지) ---
def query_ollama(prompt, model=DEFAULT_OLLAMA_MODEL, url=OLLAMA_API_URL, timeout=180): # 타임아웃 180초
    """Ollama API에 쿼리를 보내고 응답 텍스트를 반환하는 함수"""
    headers = {"Content-Type": "application/json"}
    # stream: False로 설정해야 전체 응답을 한번에 받음
    data = {
        "prompt": prompt,
        "model": model,
        "stream": False,
    }
    # print(f"[Debug] Querying Ollama model {model} with prompt: '{prompt[:100]}...'") # 디버깅 필요 시
    try:
        response = requests.post(url, headers=headers, data=json.dumps(data), timeout=timeout)
        # HTTP 오류 코드 (4xx, 5xx) 발생 시 예외 발생
        response.raise_for_status()

        # 응답 JSON 파싱 시도
        try:
            json_data = response.json()
        except json.JSONDecodeError as e:
            # 응답이 유효한 JSON이 아닌 경우
            error_msg = f"Error decoding Ollama JSON response: {e}. Status: {response.status_code}. Response text: '{response.text[:100]}...'"
            print(f"[Error] {error_msg}")
            return error_msg # 오류 메시지 반환

        # 응답 구조 확인 및 결과 추출
        if "response" in json_data and json_data["response"] is not None:
            # print(f"[Debug] Ollama response received: '{json_data['response'][:50]}...'")
            return json_data["response"].strip() # 앞뒤 공백 제거
        elif "error" in json_data:
             # Ollama API가 명시적으로 에러를 반환한 경우
             error_msg = f"Error: Ollama API returned an error: {json_data['error']}"
             print(f"[Error] {error_msg}")
             return error_msg
        else:
             # 예상치 못한 응답 형식 (response 키가 없거나 null인 경우 포함)
             error_msg = f"Error: Unexpected Ollama response format or null response. Received: {str(json_data)[:200]}..."
             print(f"[Error] {error_msg}")
             return error_msg

    except requests.exceptions.Timeout:
        error_msg = f"Error: Request to Ollama timed out after {timeout} seconds."
        print(f"[Error] {error_msg}")
        return error_msg
    except requests.exceptions.RequestException as e:
        # 네트워크 오류, 연결 오류 등 requests 관련 모든 예외 처리
        error_msg = f"Error querying Ollama: Network or connection error - {e}"
        print(f"[Error] {error_msg}")
        return error_msg
    except Exception as e:
        # 그 외 예상치 못한 모든 오류 처리
        error_msg = f"An unexpected error occurred in query_ollama: {type(e).__name__} - {e}"
        print(f"[Error] {error_msg}")
        traceback.print_exc() # 상세 오류 내용 출력
        return error_msg


# --- 작업별 프롬프트 템플릿 (영어 요약/정보 추출 추가) ---
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

    # 관계성 평가 프롬프트 (키워드 기반)
    "comparison": """Below are two lists of keywords, each extracted from a different text (Text 1 and Text 2).
Evaluate the thematic similarity between Text 1 and Text 2 based ONLY on these keywords.
Provide a single similarity score between 0.0 (no similarity) and 1.0 (very high similarity).
Output ONLY the numerical score, rounded to two decimal places (e.g., 0.75).

Keywords from Text 1:
[KEYWORDS1]

Keywords from Text 2:
[KEYWORDS2]""",

    # [NEW] 영어 요약 및 정보 추출용 프롬프트 (LLM에게 보낼 최종 영어 프롬프트 템플릿)
    "summarize_info_en": """Please read the following text. Provide a concise summary in English (2-3 sentences) capturing the main points. Also, list any key factual information (like names, dates, decisions, specific steps, locations mentioned) in bullet points, also in English. If no specific key info is found, state "Key Info: None". Use the following format exactly:
Summary:
[Your summary here]

Key Info:
- [Key info 1]
- [Key info 2]
...

[TEXT]"""
}

# --- 내용 유형에 따른 동적 프롬프트 생성 함수 ---
def create_adaptive_prompt(user_input_ko, task_type, content_type):
    """
    내용 유형에 따라 작업 프롬프트를 동적으로 조정하고 영어로 번역합니다.
    (함수 내용은 이전 답변과 동일, 내부에서 translate_text 사용)
    """
    base_prompt_template = task_prompts[task_type] # 기본 영어 템플릿
    adapted_prompt_template = base_prompt_template # 기본값 설정

    # 내용 유형에 따른 프롬프트 조정 (영어 템플릿 기준)
    if task_type == "memo":
        if content_type == "meeting_notes":
            adapted_prompt_template = "Based on the following meeting notes, create clear bullet points for **key discussion points, decisions made, and action items (including responsible persons if mentioned)**:\n[TEXT]"
        elif content_type == "idea_brainstorming":
            adapted_prompt_template = "From the following brainstorming content, organize the **core ideas and related key points** into bullet points:\n[TEXT]"
        elif content_type == "todo_list":
             adapted_prompt_template = "Reformat the following to-do list into clear and concise bullet points:\n[TEXT]"
        elif content_type == "technical_explanation":
             adapted_prompt_template = "From the following technical explanation, create bullet points for the **main steps, components, or key takeaways**:\n[TEXT]"
        else: # 다른 유형은 기본 메모 프롬프트 사용
            adapted_prompt_template = task_prompts["memo"] # 명시적으로 기본 프롬프트 사용

    elif task_type == "summarize":
        if content_type == "technical_explanation":
             adapted_prompt_template = "Summarize the following technical text in three sentences, focusing on the **core purpose, main methodology/process (if any), and significant results or conclusions**:\n[TEXT]"
        elif content_type == "meeting_notes":
             adapted_prompt_template = "Provide a three-sentence summary of the following meeting notes, highlighting the **most important discussion outcomes and decisions**:\n[TEXT]"
        elif content_type == "personal_reflection":
             adapted_prompt_template = "Summarize the main themes or feelings expressed in the following personal reflection in three sentences:\n[TEXT]"
        else: # 다른 유형은 기본 요약 프롬프트 사용
            adapted_prompt_template = task_prompts["summarize"] # 명시적으로 기본 프롬프트 사용

    # 사용자 입력(ko)을 영어로 번역 ('auto' 사용 가능)
    user_input_en = translate_text(user_input_ko, 'auto', 'en')
    if user_input_en.startswith("Error"):
        raise Exception(f"Failed to translate user input for adaptive prompt: {user_input_en}")

    # 영어 템플릿에 번역된 영어 사용자 입력을 삽입
    final_prompt_en = adapted_prompt_template.replace("[TEXT]", user_input_en)
    return final_prompt_en


# --- 핵심 실행 로직 함수 (Ollama 호출 및 번역) ---
def execute_ollama_task(english_prompt, model=DEFAULT_OLLAMA_MODEL):
    """
    Ollama에 영어 프롬프트를 보내고, 응답을 한국어로 번역하여 반환합니다.
    (함수 내용은 이전 답변과 동일, 내부에서 query_ollama 및 translate_text 사용)
    """
    # Ollama에 쿼리 (영어 프롬프트 사용)
    ollama_response_en = query_ollama(english_prompt, model=model)
    if ollama_response_en.startswith("Error"):
        # Ollama 쿼리 실패 시 오류 메시지 반환
        return ollama_response_en

    # Ollama 응답을 한국어로 번역 ('auto' 감지 시도)
    ollama_response_ko = translate_text(ollama_response_en, 'auto', 'ko')
    # 번역 결과 반환 (성공 또는 번역 오류 메시지)
    return ollama_response_ko


# --- 2단계 실행 함수: 분류 -> 적응형 프롬프트 -> 실행 ---
def execute_adaptive_ollama_task(user_input_ko, task_type, model=DEFAULT_OLLAMA_MODEL):
    """
    내용 유형 분석 후 적응형 프롬프트를 사용하여 Ollama 작업을 수행하고 결과를 반환합니다.
    (함수 내용은 이전 답변과 동일, 내부에서 분류, create_adaptive_prompt, execute_ollama_task 호출)
    """
    content_type = "unknown" # 기본 내용 유형

    # --- 1단계: 내용 유형 분석 ---
    try:
        print("[1단계] 내용 유형 분석 중...")
        # 분류 프롬프트 생성 (한국어 사용자 입력 포함)
        # 중요: CLASSIFY 프롬프트 자체는 영어지만, 내부 [TEXT]에 한국어가 들어갈 수 있음
        # translate_text('auto')를 사용하여 전체 프롬프트를 영어로 번역 시도
        classify_prompt_with_ko_text = task_prompts['classify'].replace("[TEXT]", user_input_ko)
        classify_prompt_en = translate_text(classify_prompt_with_ko_text, 'auto', 'en') # 'auto' 감지 사용

        if classify_prompt_en.startswith("Error"):
            print(f"  [경고] 내용 분석 프롬프트 번역 실패: {classify_prompt_en}. 기본 프롬프트를 사용합니다.")
            # content_type은 'unknown'으로 유지
        else:
            # Ollama에 내용 분류 요청 (영어 프롬프트 사용)
            classification_result_en = query_ollama(classify_prompt_en, model=model)
            # print(f"  [Debug] Raw classification result: '{classification_result_en}'")

            if classification_result_en.startswith("Error"):
                 print(f"  [경고] 내용 유형 분석 실패: {classification_result_en}. 기본 프롬프트를 사용합니다.")
                 # content_type은 'unknown'으로 유지
            else:
                # Ollama 응답에서 유형 레이블만 추출 시도 (간단한 처리)
                if classification_result_en and isinstance(classification_result_en, str):
                    # 응답이 여러 줄일 수 있으므로 첫 줄만 사용하고 소문자로 변환 후 앞뒤 공백 제거
                    detected_type = classification_result_en.splitlines()[0].strip().lower()
                else:
                    detected_type = "" # 유효하지 않은 응답 처리

                # 예상된 레이블 목록
                expected_types = ["meeting_notes", "idea_brainstorming", "technical_explanation",
                                  "personal_reflection", "todo_list", "general_information", "other"]

                if detected_type in expected_types:
                    content_type = detected_type
                    print(f"  감지된 내용 유형: {content_type}")
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
            user_input_en = translate_text(user_input_ko, 'auto', 'en')
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


# --- Comparison 기능 함수 (task='index' 찾도록 수정) ---
def perform_comparison_task(model=DEFAULT_OLLAMA_MODEL):
    """로그 파일에서 'index' 작업 결과를 보여주고 사용자가 선택한 2개의 키워드 유사성 점수를 계산"""
    keyword_logs = []
    try:
        if not os.path.exists(LOG_FILENAME):
            return "[오류] 로그 파일을 찾을 수 없습니다. 'index' 작업을 먼저 수행해주세요."

        with open(LOG_FILENAME, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    log_entry = json.loads(line)
                    # [수정] 'index' 작업이고, 'output'(키워드)과 'metadata.filepath' 있는지 확인
                    if (log_entry.get('task') == 'index' and # task 이름 변경 확인
                        'output' in log_entry and
                        isinstance(log_entry.get('output'), str) and # output이 문자열인지
                        ':' in log_entry['output'] and # 키워드 형식인지 (간단 체크)
                        not log_entry['output'].startswith("Error:") and # 오류 메시지가 아닌지
                        # 영어 키워드 로그는 비교에서 제외 (한국어 키워드만 비교 가정)
                        not log_entry['output'].startswith("[en]") and
                        isinstance(log_entry.get('metadata'), dict) and # 메타데이터가 딕셔너리인지
                        'filepath' in log_entry['metadata']): # 파일경로가 있는지

                        keyword_logs.append({
                            "timestamp": log_entry.get('timestamp', 'N/A'),
                            "filepath": log_entry['metadata']['filepath'], # 파일 경로 저장
                            "filename": os.path.basename(log_entry['metadata']['filepath']), # 파일 이름만 표시용
                            "output": log_entry['output'] # 한국어 키워드 결과 저장
                        })
                except (json.JSONDecodeError, KeyError, TypeError):
                    # 로그 라인 파싱 또는 구조 오류 시 조용히 건너<0xEB><0x84>기
                    # print(f"[Debug] Skipping log line {line_num} due to parsing/structure error.")
                    continue
                except Exception as e: # 그 외 예상치 못한 오류 처리
                    print(f"[경고] 로그 파일 '{LOG_FILENAME}'의 {line_num}번째 라인 처리 중 오류: {type(e).__name__}")
                    continue

    except FileNotFoundError:
         return "[오류] 로그 파일을 찾을 수 없습니다."
    except Exception as e:
        return f"[오류] 로그 파일 읽기 중 오류 발생: {e}"

    if len(keyword_logs) < 2:
        return f"[오류] 비교할 유효한 'index' 로그(한국어 키워드 포함)가 2개 이상 필요합니다. 현재 {len(keyword_logs)}개. 문서를 인덱싱해주세요."

    # --- 사용자에게 목록 보여주기 (파일 이름 기반) ---
    print("\n--- 비교 가능한 문서 목록 (키워드 기준) ---")
    for i, log_data in enumerate(keyword_logs):
        print(f"{i+1}. [{log_data['timestamp']}] File: \"{log_data['filename']}\"")
    print("----------------------------------------------")

    # --- 사용자로부터 두 개의 로그 번호 입력받기 ---
    selected_indices = []
    while len(selected_indices) < 2:
        try:
            prompt_msg = f"비교할 {'첫' if not selected_indices else '두'} 번째 문서 번호 (1-{len(keyword_logs)}): "
            choice_str = input(prompt_msg).strip()
            if not choice_str: continue # 빈 입력 무시

            choice_num = int(choice_str)
            selected_index = choice_num - 1 # 실제 리스트 인덱스로 변환

            if 0 <= selected_index < len(keyword_logs):
                if selected_index not in selected_indices:
                    selected_indices.append(selected_index)
                else:
                    print("[오류] 이미 선택한 문서입니다. 다른 번호를 입력해주세요.")
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

    keywords1_ko = log1['output'] # 한국어 키워드
    keywords2_ko = log2['output']
    filename1 = log1['filename']
    filename2 = log2['filename']

    print(f"\n--- 선택된 비교 대상 ---")
    print(f"1: File \"{filename1}\"")
    print(f"2: File \"{filename2}\"")
    print("-------------------------")

    # --- Ollama 비교 요청 ---
    try:
        # 비교 프롬프트 생성 (한국어 키워드 사용)
        comparison_prompt_ko = task_prompts["comparison"]
        comparison_prompt_ko = comparison_prompt_ko.replace("[KEYWORDS1]", keywords1_ko)
        comparison_prompt_ko = comparison_prompt_ko.replace("[KEYWORDS2]", keywords2_ko)

        # 프롬프트 번역 (ko -> en) - 'auto' 감지 사용
        comparison_prompt_en = translate_text(comparison_prompt_ko, 'auto', 'en')
        if comparison_prompt_en.startswith("Error"):
            raise Exception(f"Comparison 프롬프트 번역 실패: {comparison_prompt_en}")

        print(f"\n[comparison] 작업을 Ollama({model})에게 요청합니다...")
        # Ollama 작업 실행 (결과는 영어 점수 텍스트 예상)
        comparison_result_en = query_ollama(comparison_prompt_en, model=model)
        if comparison_result_en.startswith("Error"):
             return f"[오류] 유사성 평가 중 오류 발생: {comparison_result_en}"

        # 결과에서 숫자 점수만 추출 시도 (번역 불필요)
        try:
            # 결과 텍스트에서 숫자 부분만 추출 (더 안정적인 정규식 사용)
            score_text = comparison_result_en.strip()
            # 정규식: 소수점 포함하는 숫자 (예: 0.75, 1.0, .8 등)
            match = re.search(r"(\d*\.\d+|\d+)", score_text)
            if match:
                score = float(match.group(1))
                # 점수 범위 확인 (0~1)
                if 0.0 <= score <= 1.0:
                    return f"'{filename1}'와(과) '{filename2}' 간의 키워드 기반 유사성 점수: {score:.2f}"
                else:
                    # 범위 벗어난 경우도 일단 점수는 보여줌
                    return f"계산된 유사성 점수 ({score:.2f})가 범위(0-1)를 벗어났습니다. 원본 결과: '{score_text}'"
            else:
                 # 숫자 못 찾으면 원본 반환
                 return f"유사성 평가 결과 (점수 추출 불가): '{score_text}'"
        except ValueError:
             # float 변환 실패 시
             return f"유사성 평가 결과 (텍스트, 점수 변환 불가): '{comparison_result_en}'"

    except Exception as e:
        return f"[오류] Comparison 작업 처리 중 문제 발생: {type(e).__name__} - {e}"


# --- 문서 관련 함수 ---
def get_document_paths(doc_dir):
    """지정된 디렉토리에서 모든 .md 파일 경로 리스트를 반환"""
    doc_path = Path(doc_dir)
    if not doc_path.is_dir():
        print(f"[오류] 문서 디렉토리 '{doc_dir}'를 찾을 수 없거나 디렉토리가 아닙니다.")
        return []
    # rglob: 하위 디렉토리 포함 검색
    return list(doc_path.rglob('*.md'))

def read_document_content(filepath):
    """파일 경로를 받아 내용을 읽어 반환"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        print(f"[오류] 파일을 찾을 수 없습니다: {filepath}")
        return None
    except Exception as e:
        print(f"[오류] 파일 읽기 오류 ({filepath}): {e}")
        return None


# --- 키워드 및 요약 인덱싱 함수 ---
def index_documents(doc_dir, log_filename, model=DEFAULT_OLLAMA_MODEL):
    """'/Doc' 디렉토리의 .md 파일에 대해 키워드(ko)와 요약/정보(en)를 추출하고 로그에 기록"""
    print(f"\n--- '{doc_dir}' 내 .md 파일 인덱싱 (키워드 & 요약) 시작 ---")
    doc_paths = get_document_paths(doc_dir)
    if not doc_paths:
        print("인덱싱할 .md 파일이 없습니다.")
        return

    # 기존 로그에서 이미 처리된 파일 경로 로드 (중복 방지용)
    processed_files = set()
    if os.path.exists(log_filename):
        try:
            with open(log_filename, 'r', encoding='utf-8') as f:
                for line in f:
                    try:
                        log_entry = json.loads(line)
                        # task 이름 'index'로 확인
                        if log_entry.get('task') == 'index' and isinstance(log_entry.get('metadata'), dict) and 'filepath' in log_entry['metadata']:
                            processed_files.add(log_entry['metadata']['filepath'])
                    except (json.JSONDecodeError, KeyError, TypeError):
                        continue # 파싱/구조 오류 무시
        except Exception as e:
            print(f"[경고] 기존 로그 파일 읽기 중 오류 (중복 체크 영향): {e}")

    total_files = len(doc_paths)
    indexed_count = 0
    skipped_count = 0
    error_count = 0

    # 각 파일 처리
    for idx, filepath in enumerate(doc_paths, 1):
        filepath_str = str(filepath)
        print(f"\n  ({idx}/{total_files}) 처리 중: {filepath.name}")

        # 중복 체크
        if filepath_str in processed_files:
            print(f"    - 이미 로그에 존재하여 건너<0xEB><0x84>니다.")
            skipped_count += 1
            continue

        # 파일 내용 읽기
        content_ko = read_document_content(filepath)
        if content_ko is None or not content_ko.strip():
            print(f"    - 내용을 읽을 수 없거나 비어있어 건너<0xEB><0x84>니다.")
            error_count += 1
            continue

        # 결과 저장 변수 초기화 (오류 발생 대비)
        keywords_ko = "Error: Keyword extraction failed"
        summary_en = "Error: Summary/Info extraction failed"
        current_file_success = False # 현재 파일 처리 성공 여부 플래그

        # 파일 처리 시작 (예외 처리 블록)
        try:
            # --- 1. 키워드 추출 (한국어 결과 목표) ---
            print("      - 1/2: 키워드 추출 중...")
            keyword_prompt_ko = task_prompts["keyword"].replace("[TEXT]", content_ko)
            keyword_prompt_en = translate_text(keyword_prompt_ko, "auto", "en") # auto 감지 사용
            if keyword_prompt_en.startswith("Error"):
                # 프롬프트 번역 실패 시 예외 발생시켜 아래에서 잡도록 함
                raise Exception(f"키워드 프롬프트 번역 실패: {keyword_prompt_en}")

            keyword_result_en = query_ollama(keyword_prompt_en, model=model)
            if keyword_result_en.startswith("Error"):
                raise Exception(f"Ollama 키워드 추출 실패: {keyword_result_en}")

            # 키워드 결과(en) -> 한국어 번역
            kw_ko_translated = translate_text(keyword_result_en, "en", "ko")
            if kw_ko_translated.startswith("Error"):
                 print(f"      [경고] 키워드 결과 번역 실패. 영어 결과를 로그에 기록합니다.")
                 keywords_ko = f"[en] {keyword_result_en}" # 번역 실패 시 영어 결과 저장
            else:
                 keywords_ko = kw_ko_translated # 성공 시 한국어 키워드

            # --- 2. 영어 요약/정보 추출 ---
            print("      - 2/2: 영어 요약/정보 추출 중...")
            # 원본 한국어 내용을 영어로 먼저 번역 ('auto' 감지 사용)
            content_en = translate_text(content_ko, "auto", "en")
            if content_en.startswith("Error"):
                raise Exception(f"콘텐츠 영어 번역 실패: {content_en}")

            # 영어 요약 프롬프트 생성
            summarize_info_request_en = task_prompts["summarize_info_en"].replace("[TEXT]", content_en)

            # Ollama 요약/정보 추출 요청 (결과는 영어)
            summary_info_result_en = query_ollama(summarize_info_request_en, model=model)
            if summary_info_result_en.startswith("Error"):
                raise Exception(f"Ollama 요약/정보 추출 실패: {summary_info_result_en}")
            else:
                summary_en = summary_info_result_en # 성공 시 영어 요약 결과 저장
                current_file_success = True # 키워드와 요약 모두 성공

        except Exception as e:
            # 키워드 추출 또는 요약 추출 과정에서 오류 발생 시
            print(f"    [오류] 파일 처리 중 예외 발생: {e}")
            # error_count는 finally 블록에서 처리

        # --- 3. 로깅 (성공/실패 여부 기록) ---
        finally:
            # 성공 여부 메시지 출력
            if current_file_success:
                 indexed_count += 1
                 print(f"    - 인덱싱 성공.")
            else:
                 error_count += 1 # try 블록에서 예외 발생 시 error_count 증가
                 print(f"    - 인덱싱 중 오류 발생. 로그에 오류 정보 기록.")

            # 로그 항목 구성 (오류 발생 시에도 오류 메시지가 변수에 담겨 저장됨)
            log_entry = {
                "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "task": "index", # 태스크 이름 명시
                "input_source": f"file: {filepath.name}",
                "output": keywords_ko, # 한국어 키워드 또는 오류 메시지
                "summary_en": summary_en, # 영어 요약/정보 또는 오류 메시지
                "metadata": {"filepath": filepath_str}, # 파일 경로 메타데이터
                "model_used": model
            }
            # 로그 파일에 추가 시도
            try:
                os.makedirs(LOG_DIR, exist_ok=True) # 로그 디렉토리 확인/생성
                with open(log_filename, 'a', encoding='utf-8') as f:
                    f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')
                # print(f"    - 로그 기록 완료.") # 성공/실패 메시지는 위에서 출력
            except Exception as log_e:
                print(f"    [오류] 로그 파일 저장 실패: {log_e}")
                # 로그 저장 실패는 별도 카운트하지 않음

    # 최종 인덱싱 결과 출력
    print(f"\n--- 인덱싱 완료 ---")
    print(f"  성공: {indexed_count}, 건너<0xEB><0x9B><0x84>: {skipped_count}, 처리 오류: {error_count} (로그 저장 실패 별도)")


# --- 키워드 기반 관련 문서 검색 함수 (반환값 변경됨) ---
def find_related_documents_by_keywords(query_keywords_ko, log_filename, model=DEFAULT_OLLAMA_MODEL, top_n=3):
    """로그에서 키워드를 읽어 쿼리 키워드와 비교하여 가장 유사한 문서 N개의 정보(파일경로, 영어 요약)를 반환"""
    print(f"\n--- 키워드 기반 관련 문서 검색 시작 (쿼리: '{query_keywords_ko[:30]}...') ---")
    indexed_docs = [] # 문서 정보(파일경로, 키워드, 요약)를 담을 리스트
    try:
        if not os.path.exists(log_filename):
             print("[오류] 로그 파일이 없습니다. 먼저 6번(index) 작업을 수행하세요.")
             return []

        # 로그 파일 읽기
        with open(log_filename, 'r', encoding='utf-8') as f:
            for line in f:
                 try:
                     log_entry = json.loads(line)
                     # [수정] 'index' 작업이고, 필요한 필드(output(ko), summary_en(ok), metadata.filepath) 있는지 확인
                     if (log_entry.get('task') == 'index' and
                         'output' in log_entry and
                         isinstance(log_entry.get('output'), str) and
                         ':' in log_entry['output'] and # 키워드 형식 체크
                         not log_entry['output'].startswith("Error:") and
                         not log_entry['output'].startswith("[en]") and # 한국어 키워드만 대상
                         'summary_en' in log_entry and # 영어 요약 필드 확인
                         isinstance(log_entry.get('summary_en'), str) and # 요약이 문자열인지
                         not log_entry['summary_en'].startswith("Error:") and # 요약 오류 아닌지 확인
                         isinstance(log_entry.get('metadata'), dict) and
                         'filepath' in log_entry['metadata']):

                         indexed_docs.append({
                             "filepath": log_entry['metadata']['filepath'],
                             "keywords_ko": log_entry['output'],
                             "summary_en": log_entry['summary_en'] # 영어 요약 정보 추가
                         })
                 except (json.JSONDecodeError, KeyError, TypeError):
                     continue # 파싱/구조 오류 무시
    except Exception as e:
        print(f"[오류] 로그 파일 읽기 중 오류: {e}")
        return []

    if not indexed_docs:
        print("[정보] 비교할 유효한 인덱스 로그가 없습니다.")
        return []

    print(f"로그에서 {len(indexed_docs)}개의 유효한 인덱스 정보를 로드했습니다. 유사성 비교 시작...")

    results_with_scores = []
    comparison_count = 0
    comparison_errors = 0

    # 각 인덱스 정보와 쿼리 키워드 비교
    for doc_data in indexed_docs:
        doc_filepath = doc_data['filepath']
        doc_keywords_ko = doc_data['keywords_ko']
        doc_summary_en = doc_data['summary_en'] # 반환할 요약 정보
        comparison_count += 1
        print(f"  ({comparison_count}/{len(indexed_docs)}) 비교 중: Query <-> {os.path.basename(doc_filepath)}")

        try:
            # 비교 프롬프트 생성 및 번역
            comparison_prompt_ko = task_prompts["comparison"].replace("[KEYWORDS1]", query_keywords_ko).replace("[KEYWORDS2]", doc_keywords_ko)
            comparison_prompt_en = translate_text(comparison_prompt_ko, 'auto', 'en')
            if comparison_prompt_en.startswith("Error"):
                 print(f"    [경고] 비교 프롬프트 번역 실패, 건너<0xEB><0x84>니다.")
                 comparison_errors += 1
                 continue

            # Ollama 비교 작업 실행 및 점수 추출
            comparison_result_en = query_ollama(comparison_prompt_en, model=model)
            if comparison_result_en.startswith("Error"):
                 print(f"    [경고] Ollama 유사성 평가 실패: {comparison_result_en}, 건너<0xEB><0x84>니다.")
                 comparison_errors += 1
                 continue

            score = -1.0 # 기본 오류 값
            try:
                # 점수 파싱 로직 (정규식 사용)
                score_text = comparison_result_en.strip()
                match = re.search(r"(\d*\.\d+|\d+)", score_text)
                if match:
                    parsed_score = float(match.group(1))
                    if 0.0 <= parsed_score <= 1.0:
                        score = parsed_score
                    else:
                        print(f"    [경고] 점수 범위 벗어남 ({parsed_score:.2f}). 결과 무시.")
                else:
                    print(f"    [경고] 점수 추출 불가. 응답: '{score_text}'. 결과 무시.")
            except ValueError:
                 print(f"    [경고] 점수 변환 실패. 응답: '{comparison_result_en}'. 결과 무시.")

            # 유효한 점수 얻었을 경우 결과 리스트에 추가
            if score >= 0.0:
                 results_with_scores.append({
                     "filepath": doc_filepath,
                     "score": score,
                     "summary_en": doc_summary_en # 요약 정보 포함
                 })
                 print(f"    - 유사성 점수: {score:.2f}")

        except Exception as e:
            print(f"    [오류] 비교 처리 중 예외 발생: {e}")
            comparison_errors += 1

    print(f"--- 유사성 비교 완료 (오류: {comparison_errors}건) ---")

    # 점수 기준으로 내림차순 정렬
    results_with_scores.sort(key=lambda x: x["score"], reverse=True)

    # 상위 N개 결과 선택
    top_results = results_with_scores[:top_n]
    print(f"상위 {len(top_results)}개 관련 문서 정보:")
    for res in top_results:
        print(f"  - {os.path.basename(res['filepath'])} (Score: {res['score']:.2f})")

    # [수정] 파일 경로만 반환하는 대신, 필요한 정보(파일경로, 영어 요약)를 담은 딕셔너리 리스트 반환
    return [{"filepath": res["filepath"], "summary_en": res["summary_en"]} for res in top_results]


# --- 메인 함수 ---
def main():
    """메인 함수: 사용자 입력, 작업 선택, Ollama 쿼리, 결과 출력 및 로깅"""
    model_to_use = DEFAULT_OLLAMA_MODEL

    # 작업 매핑 (task 이름 변경 반영)
    task_mapping = {
        '1': 'summarize', '2': 'memo', '3': 'keyword', '4': 'chat',
        '5': 'comparison',
        '6': 'index', # 문서 인덱싱 (키워드+요약)
        '7': 'related_task', # 관계도(요약) 기반 작업
    }

    # 로그/문서 디렉토리 생성 및 확인
    try:
        os.makedirs(DOC_DIR, exist_ok=True)
        os.makedirs(LOG_DIR, exist_ok=True)
        print(f"문서 디렉토리: {DOC_DIR}")
        print(f"로그 디렉토리: {LOG_DIR}")
    except OSError as e:
        print(f"[오류] 디렉토리 생성 실패: {e}")
        return # 디렉토리 생성 못하면 종료

    # 메인 루프 시작
    while True:
        print("\n" + "="*10 + " 작업 선택 " + "="*10)
        print("1. 요약 (Summarize) [단일 텍스트, 최적화]")
        print("2. 메모 (Memo) [단일 텍스트, 최적화]")
        print("3. 키워드 추출 (Keyword) [단일 텍스트 대상]")
        print("4. 일반 대화 (Chat)")
        print("5. 로그 비교 (Comparison) [수동 선택]")
        print("--- 문서 관리 & 활용 ---")
        print(f"6. 문서 인덱싱 (index) ['/Doc' 내 .md 키워드(ko)+요약(en) 추출]")
        print(f"7. 주제 관련 작업 (related_task) [인덱스된 요약 활용]")
        print("exit: 종료")
        print("="*32)

        choice = input("선택: ").lower().strip()
        if choice == 'exit':
            break

        # 각 루프 시작 시 변수 초기화
        task_name = "unknown"
        result = "오류: 처리되지 않음" # 기본 결과값
        log_this_interaction = True # 기본적으로 로깅 수행
        user_input_ko = "" # 사용자 입력 저장용 변수 초기화

        # 작업 처리 (try...except로 감싸기)
        try:
            # --- 작업 분기 ---
            if choice == '5': # Comparison 작업
                task_name = "comparison"
                comparison_output = perform_comparison_task(model=model_to_use)
                # Comparison 결과는 즉시 출력하고 로깅 안 함
                print("\n" + "="*30); print(f"결과 ({task_name}):"); print(comparison_output); print("="*30 + "\n")
                log_this_interaction = False

            elif choice == '6': # 문서 인덱싱
                 task_name = "index"
                 index_documents(DOC_DIR, LOG_FILENAME, model=model_to_use)
                 log_this_interaction = False # 인덱싱 작업 자체는 메인 로그에 남기지 않음 (내부에서 개별 로깅)

            elif choice == '7': # 주제 관련 작업 (요약 활용)
                task_name = "related_task" # 기본 작업명
                user_query_ko = input("질문 또는 정리할 주제를 입력하세요: ")
                if not user_query_ko.strip():
                    print("[알림] 입력이 비어 있습니다.")
                    log_this_interaction = False # 빈 입력은 처리/로깅 안함
                    continue # 다음 루프로
                user_input_ko = user_query_ko # 로깅을 위해 입력값 저장

                # 1. 쿼리 키워드 추출
                print("--- 1단계: 쿼리 키워드 추출 ---")
                query_keyword_prompt_ko = task_prompts["keyword"].replace("[TEXT]", user_query_ko)
                query_keyword_prompt_en = translate_text(query_keyword_prompt_ko, "auto", "en")
                if query_keyword_prompt_en.startswith("Error"): raise Exception(f"쿼리 키워드 프롬프트 번역 실패: {query_keyword_prompt_en}")
                query_keywords_en = query_ollama(query_keyword_prompt_en, model=model_to_use)
                if query_keywords_en.startswith("Error"): raise Exception(f"쿼리 키워드 추출 실패: {query_keywords_en}")
                query_keywords_ko = translate_text(query_keywords_en, "en", "ko")
                if query_keywords_ko.startswith("Error"): raise Exception(f"쿼리 키워드 번역 실패: {query_keywords_ko}")
                print(f"추출된 쿼리 키워드(ko):\n{query_keywords_ko}")

                # 2. 관련 문서 정보(요약 포함) 검색
                print("--- 2단계: 관련 문서 정보 검색 ---")
                # find_related... 함수는 이제 [{'filepath': ..., 'summary_en': ...}, ...] 형태의 리스트 반환
                related_docs_info = find_related_documents_by_keywords(query_keywords_ko, LOG_FILENAME, model=model_to_use, top_n=3)

                if not related_docs_info:
                    # 관련 문서 못 찾으면 Fallback
                    print("[알림] 관련 문서를 찾지 못했습니다. 일반 Chat 방식으로 처리합니다.")
                    task_name = "chat_fallback" # 작업명 변경
                    english_prompt = translate_text(user_query_ko, 'auto', 'en')
                    if english_prompt.startswith("Error"): raise Exception(english_prompt)
                    result = execute_ollama_task(english_prompt, model=model_to_use) # 결과 할당
                else:
                    # 관련 문서 찾았으면 요약 기반 프롬프트 생성
                    print("--- 3단계: 관련 문서 영어 요약으로 프롬프트 생성 ---")
                    augmented_context_en = "" # 영어 컨텍스트 생성
                    for i, doc_info in enumerate(related_docs_info):
                        filename = os.path.basename(doc_info['filepath'])
                        summary = doc_info['summary_en'] # 영어 요약 사용
                        augmented_context_en += f"\n--- Relevant Document Summary {i+1}: {filename} ---\n"
                        augmented_context_en += summary + "\n"

                    # 최종 프롬프트 (한국어 질문 + 영어 요약 컨텍스트 + 한국어 지시)
                    final_prompt_ko = f"""사용자 질문/주제: {user_query_ko}

다음은 관련성이 높은 문서들의 영어 요약본입니다:
{augmented_context_en}
위 영어 요약 내용을 바탕으로 사용자의 질문에 답하거나 주제를 한국어로 정리해주세요."""

                    # 4. 최종 프롬프트를 영어로 번역하여 Ollama 실행
                    print("--- 4단계: 최종 작업 요청 ---")
                    final_prompt_en = translate_text(final_prompt_ko, "auto", "en") # 전체 프롬프트를 영어로
                    if final_prompt_en.startswith("Error"):
                        raise Exception(f"최종 프롬프트 번역 실패: {final_prompt_en}")

                    # execute_ollama_task는 내부에서 영어 프롬프트로 Ollama 호출 후, 결과를 한국어로 번역
                    result = execute_ollama_task(final_prompt_en, model=model_to_use) # 결과 할당

            elif choice in ('1', '2', '3', '4'): # 기존 단일 입력 작업
                 user_input_ko_single = input("작업할 텍스트 또는 질문을 입력하세요: ")
                 if not user_input_ko_single.strip():
                     print("[알림] 입력이 비어 있습니다.")
                     log_this_interaction = False
                     continue
                 user_input_ko = user_input_ko_single # 로깅용 입력값 저장

                 # task_name 설정
                 if choice not in task_mapping:
                     print("[오류] 내부 오류: task_mapping에 해당 선택지가 없습니다.")
                     log_this_interaction = False
                     continue
                 task_name = task_mapping[choice]

                 print(f"\n[{task_name}] 작업을 Ollama({model_to_use})에게 요청합니다...")

                 # 작업 유형별 처리
                 if choice == '4': # Chat
                     english_prompt = translate_text(user_input_ko, 'auto', 'en')
                     if english_prompt.startswith("Error"): raise Exception(english_prompt)
                     result = execute_ollama_task(english_prompt, model=model_to_use)
                 elif choice in ('1', '2'): # Summarize, Memo (Adaptive)
                     result = execute_adaptive_ollama_task(user_input_ko, task_name, model=model_to_use)
                 elif choice == '3': # Keyword
                     keyword_prompt_ko = task_prompts[task_name].replace("[TEXT]", user_input_ko)
                     english_prompt = translate_text(keyword_prompt_ko, "auto", "en")
                     if english_prompt.startswith("Error"): raise Exception(english_prompt)
                     keyword_result_en = query_ollama(english_prompt, model=model_to_use)
                     if keyword_result_en.startswith("Error"):
                         result = keyword_result_en # 오류 결과 사용
                     else:
                         # 키워드 결과(en) -> 한국어 번역
                         keyword_result_ko = translate_text(keyword_result_en, "en", "ko")
                         # 번역 성공 시 한국어 결과, 실패 시 [en] 접두사 붙여 영어 결과 사용
                         result = keyword_result_ko if not keyword_result_ko.startswith("Error") else f"[en] {keyword_result_en}"

            else: # 잘못된 선택
                print("[오류] 잘못된 선택입니다. 메뉴에 있는 번호나 'exit'를 입력해주세요.")
                log_this_interaction = False
                task_name = "invalid_choice" # 잘못된 선택 명시

            # --- [통합] 결과 출력 (결과를 출력해야 하는 유효 작업 완료 시) ---
            # task_name이 설정되었고, 로깅 안하는 특수 작업이 아닌 경우
            if task_name not in ["unknown", "invalid_choice", "index", "comparison"]:
                print("\n" + "="*30)
                print(f"결과 ({task_name}):")
                # result 변수에 담긴 최종 결과 (한국어 또는 오류 메시지) 출력
                print(result)
                print("="*30 + "\n")

            # --- [통합] 로깅 (오류 아닐 경우 & 로깅 플래그 True & 유효 작업일 때) ---
            if log_this_interaction and isinstance(result, str) and not result.startswith("Error:") and task_name not in ["unknown", "invalid_choice"]:
                try:
                    # 로그 항목 구성 (user_input_ko 변수 사용 확인)
                    log_entry = {
                        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                        "task": task_name,
                        "input": user_input_ko, # 해당 루프의 사용자 입력 저장
                        "output": result, # 최종 결과 저장
                        "model_used": model_to_use
                        # 필요 시 추가 메타 정보 로깅 가능 (예: related_task 시 사용된 문서 요약 등)
                    }
                    os.makedirs(LOG_DIR, exist_ok=True) # 로그 디렉토리 재확인
                    with open(LOG_FILENAME, 'a', encoding='utf-8') as f:
                        f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')
                except Exception as log_e:
                    print(f"[오류] 로그 파일 저장 실패: {log_e}")

        # --- 메인 예외 처리 ---
        except Exception as e:
            print(f"\n[!!! 작업 '{task_name}' 처리 중 오류 발생 !!!]")
            print(f"오류 상세: {type(e).__name__} - {e}")
            print("--- Traceback ---")
            traceback.print_exc() # 상세 오류 스택 출력
            print("--- End Traceback ---")
            print("다음 작업을 계속 진행합니다.")
            # 오류 발생 시 해당 루프의 로깅은 자동으로 건너뜀

# --- 스크립트 실행 시작점 ---
if __name__ == "__main__":
    # 시작 메시지 및 필수 디렉토리 확인
    print(f"스크립트 시작: {datetime.datetime.now()}")
    print(f"사용 모델: {DEFAULT_OLLAMA_MODEL}")
    try:
        os.makedirs(DOC_DIR, exist_ok=True)
        os.makedirs(LOG_DIR, exist_ok=True)
        print(f"문서 디렉토리 확인: {DOC_DIR}")
        print(f"로그 파일 위치 확인: {LOG_FILENAME}")
    except OSError as e:
        print(f"[치명적 오류] 필수 디렉토리 생성 불가: {e}. 스크립트를 종료합니다.")
        exit(1) # 디렉토리 없으면 실행 의미 없음

    # 메인 함수 실행 (키보드 인터럽트 처리 포함)
    try:
        main()
    except KeyboardInterrupt:
        print("\n[알림] 사용자에 의해 스크립트가 중단되었습니다.")
    finally:
        # 스크립트 종료 메시지
        print(f"\n스크립트 종료: {datetime.datetime.now()}")


