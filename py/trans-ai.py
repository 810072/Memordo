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

# --- RAG 관련 라이브러리 ---
# pip install sentence-transformers chromadb
from sentence_transformers import SentenceTransformer
import chromadb

# --- 상수 정의 ---
OLLAMA_API_URL = "http://localhost:11434/api/generate"
DEFAULT_OLLAMA_MODEL = "llama3.1:8b"

# 경로 설정 (스크립트 위치 기준 상대 경로 또는 필요시 절대 경로 사용)
BASE_DIR = os.path.dirname(os.path.abspath(__file__)) # 스크립트가 있는 디렉토리
DOC_DIR = os.path.join(BASE_DIR, "Doc")      # 문서 디렉토리
LOG_DIR = os.path.join(BASE_DIR, "log")      # 로그 디렉토리
CHROMA_DB_PATH = os.path.join(BASE_DIR, "chroma_db_st_google") # ChromaDB 저장 경로
LOG_FILENAME = os.path.join(LOG_DIR, "interaction_log_st_google.jsonl")

# --- SentenceTransformer 모델 설정 ---
# 영어 임베딩에 적합한 모델 선택 (Hugging Face 모델 허브에서 확인 가능)
# 예: 'all-MiniLM-L6-v2', 'all-mpnet-base-v2' 등
SBERT_MODEL_NAME = 'all-MiniLM-L6-v2'
SBERT_MODEL = None # 전역 변수로 모델 관리

# --- ChromaDB 클라이언트 및 컬렉션 설정 ---
CHROMA_CLIENT = None
CHROMA_COLLECTION_NAME = "documents_ko_en_sbert"
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
            # 프로그램 지속이 어려우므로 예외 발생 또는 종료 처리 필요
            raise SystemExit(f"SBERT 모델 로드 실패: {e}")
    return SBERT_MODEL

# --- 유틸리티 함수: ChromaDB 초기화 ---
def initialize_chromadb():
    global CHROMA_CLIENT, CHROMA_COLLECTION
    if CHROMA_CLIENT is None:
        try:
            # 디스크에 DB를 저장하고 재사용하기 위해 PersistentClient 사용
            os.makedirs(CHROMA_DB_PATH, exist_ok=True)
            CHROMA_CLIENT = chromadb.PersistentClient(path=CHROMA_DB_PATH)
            print(f"ChromaDB 클라이언트 초기화 완료 (저장 경로: {CHROMA_DB_PATH})")
        except Exception as e:
            print(f"[치명적 오류] ChromaDB 클라이언트 초기화 실패: {e}")
            raise SystemExit(f"ChromaDB 클라이언트 초기화 실패: {e}")

    if CHROMA_COLLECTION is None and CHROMA_CLIENT:
        try:
            # 컬렉션 가져오기 또는 생성 (임베딩 함수는 직접 제공하므로 지정 안 함)
            CHROMA_COLLECTION = CHROMA_CLIENT.get_or_create_collection(name=CHROMA_COLLECTION_NAME)
            print(f"ChromaDB 컬렉션 '{CHROMA_COLLECTION_NAME}' 로드/생성 완료. 현재 아이템 수: {CHROMA_COLLECTION.count()}")
        except Exception as e:
            print(f"[치명적 오류] ChromaDB 컬렉션 '{CHROMA_COLLECTION_NAME}' 가져오기/생성 실패: {e}")
            raise SystemExit(f"ChromaDB 컬렉션 가져오기/생성 실패: {e}")
    return CHROMA_COLLECTION

# --- 번역 함수 (기존 코드와 거의 동일, 약간의 디버그 메시지 수정 가능) ---
def detect_language(text):
    if not text or not isinstance(text, str) or not text.strip():
        return None
    try:
        translator = Translator()
        detected = translator.detect(text)
        return detected.lang
    except Exception as e:
        print(f"[Warning] 언어 감지 실패: {e} (텍스트: '{text[:30]}...')")
        return None

def translate_text(text, src_lang, dest_lang, retries=3, delay=1):
    if not text or not isinstance(text, str) or not text.strip():
        return "" # 빈 문자열 반환 일관성 유지

    source_language = src_lang
    if source_language is None or str(source_language).lower() == 'auto':
        detected_src = detect_language(text)
        if detected_src and detected_src in LANGUAGES:
            source_language = detected_src
        else:
            # 기본 추정: 한국어->영어 또는 영어->한국어
            source_language = 'ko' if dest_lang == 'en' else 'en'
            print(f"[Warning] 언어 감지 실패/미지원 ('{detected_src}'). 소스 언어 '{source_language}' (목표: '{dest_lang}')로 가정.")

    if dest_lang not in LANGUAGES:
        error_msg = f"Error: 유효하지 않은 목적 언어 코드: {dest_lang}"
        print(f"[Error] {error_msg}")
        return error_msg

    if source_language == dest_lang:
        return text

    translator = Translator()
    for attempt in range(retries):
        try:
            # translator = Translator(timeout=httpx.Timeout(10.0)) # 필요시 타임아웃
            translation = translator.translate(text, src=source_language, dest=dest_lang)
            if translation and hasattr(translation, 'text') and translation.text is not None:
                return translation.text
            else:
                error_msg = f"번역 결과가 예상과 다릅니다 (시도 {attempt+1}/{retries}). 입력: '{text[:50]}...', 결과: {translation}"
                print(f"[Warning] {error_msg}")
        except (RequestException, httpx.RequestError) as e:
            error_msg = f"번역 중 네트워크 오류 (시도 {attempt+1}/{retries}): {type(e).__name__} - {e}"
            print(f"[Warning] {error_msg}")
        except AttributeError as e: # 가끔 googletrans 내부에서 발생
             error_msg = f"번역 처리 중 속성 오류 (시도 {attempt+1}/{retries}): {e}"
             print(f"[Warning] {error_msg}")
        except Exception as e:
            error_msg = f"번역 중 예상치 못한 오류 (시도 {attempt+1}/{retries}): {type(e).__name__} - {e}"
            print(f"[Warning] {error_msg}")
            # traceback.print_exc() # 상세 디버깅 필요 시

        if attempt < retries - 1:
            current_delay = delay * (2 ** attempt) # Exponential backoff
            print(f"{current_delay}초 후 번역 재시도...")
            time.sleep(current_delay)
        else:
            final_error = f"Error: {retries}번 시도 후 번역 실패. 입력: '{text[:50]}...'"
            print(f"[Error] {final_error}")
            return final_error
    return f"Error: 번역 루프 후 예기치 않게 실패. 입력: '{text[:50]}...'"


# --- 임베딩 생성 함수 (SentenceTransformer 사용) ---
def get_embedding_for_text_en(text_en):
    """영문 텍스트에 대한 SentenceTransformer 임베딩 벡터를 반환."""
    if not text_en or not isinstance(text_en, str) or not text_en.strip():
        # print("[Warning] 임베딩을 위한 영어 텍스트가 비어있거나 유효하지 않습니다.")
        return None
    try:
        sbert_model = get_sbert_model() # 모델 로더 호출
        # 모델이 GPU를 사용하도록 설정되어 있다면 자동으로 활용됨
        embedding = sbert_model.encode(text_en, convert_to_tensor=False) # numpy array
        return embedding.tolist() # ChromaDB 저장을 위해 리스트로 변환
    except Exception as e:
        print(f"[오류] SentenceTransformer 임베딩 생성 중 오류 ('{text_en[:50]}...'): {e}")
        # traceback.print_exc()
        return None


# --- Ollama 쿼리 함수 (기존과 동일) ---
def query_ollama(prompt, model=DEFAULT_OLLAMA_MODEL, url=OLLAMA_API_URL, timeout=180):
    headers = {"Content-Type": "application/json"}
    data = {"prompt": prompt, "model": model, "stream": False}
    try:
        response = requests.post(url, headers=headers, data=json.dumps(data), timeout=timeout)
        response.raise_for_status()
        try:
            json_data = response.json()
        except json.JSONDecodeError as e:
            error_msg = f"Error: Ollama JSON 응답 디코딩 오류: {e}. 상태: {response.status_code}. 응답 텍스트: '{response.text[:100]}...'"
            print(f"[Error] {error_msg}")
            return error_msg
        
        if "response" in json_data and json_data["response"] is not None:
            return json_data["response"].strip()
        elif "error" in json_data:
            error_msg = f"Error: Ollama API가 오류를 반환했습니다: {json_data['error']}"
            print(f"[Error] {error_msg}")
            return error_msg
        else:
            error_msg = f"Error: 예상치 못한 Ollama 응답 형식 또는 null 응답. 수신: {str(json_data)[:200]}..."
            print(f"[Error] {error_msg}")
            return error_msg
    except requests.exceptions.Timeout:
        error_msg = f"Error: Ollama 요청 시간 초과 ({timeout}초)."
        print(f"[Error] {error_msg}")
        return error_msg
    except requests.exceptions.RequestException as e:
        error_msg = f"Error: Ollama 쿼리 중 네트워크 또는 연결 오류 - {e}"
        print(f"[Error] {error_msg}")
        return error_msg
    except Exception as e:
        error_msg = f"query_ollama에서 예상치 못한 오류 발생: {type(e).__name__} - {e}"
        print(f"[Error] {error_msg}")
        traceback.print_exc()
        return error_msg

# --- 작업별 프롬프트 템플릿 (기존과 유사, summarize_info_en 은 RAG 컨텍스트에 맞춰 수정될 수 있음) ---
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
    "summarize": "Please summarize the following text in three concise sentences, capturing the main points:\n[TEXT]",
    "memo": "Based on the following content, create bullet points highlighting the key ideas and decisions:\n[TEXT]",
    "keyword": """Analyze the following text. Identify the 5 most important keywords relevant to the main topic.
For each keyword, estimate its importance score as a decimal number between 0.0 and 1.0 (e.g., 0.75, 0.9).
Output Format Rules:
1. You MUST list exactly 5 keyword-score pairs.
2. Each pair MUST be on a new line.
3. The format for each line MUST be exactly: `keyword: score` (e.g., `artificial intelligence: 0.95`).
4. The score MUST be a decimal number between 0.0 and 1.0, inclusive.
5. Do NOT include any other text, explanations, introductions, or summaries. Output ONLY the 5 keyword-score pairs in the specified format.
[TEXT]""",
    "comparison": """Below are two lists of keywords, each extracted from a different text (Text 1 and Text 2).
Evaluate the thematic similarity between Text 1 and Text 2 based ONLY on these keywords.
Provide a single similarity score between 0.0 (no similarity) and 1.0 (very high similarity).
Output ONLY the numerical score, rounded to two decimal places (e.g., 0.75).
Keywords from Text 1:
[KEYWORDS1]
Keywords from Text 2:
[KEYWORDS2]""",
    # summarize_info_en 은 RAG 파이프라인에서 직접 사용되기보다,
    # index_documents 에서 문서 요약 생성 시 활용될 수 있음 (현재는 사용 안 함)
    "summarize_info_en": """Please read the following text. Provide a concise summary in English (2-3 sentences) capturing the main points. Also, list any key factual information (like names, dates, decisions, specific steps, locations mentioned) in bullet points, also in English. If no specific key info is found, state "Key Info: None".
Summary:
[Your summary here]
Key Info:
- [Key info 1]
...
[TEXT]"""
}

# --- 내용 유형에 따른 동적 프롬프트 생성 함수 (기존과 동일, 내부 번역 사용) ---
def create_adaptive_prompt(user_input_ko, task_type, content_type):
    base_prompt_template = task_prompts[task_type]
    adapted_prompt_template = base_prompt_template # 기본값

    if task_type == "memo":
        if content_type == "meeting_notes":
            adapted_prompt_template = "Based on the following meeting notes, create clear bullet points for **key discussion points, decisions made, and action items (including responsible persons if mentioned)**:\n[TEXT]"
        # ... (다른 content_type에 대한 memo 프롬프트 생략, 기존 코드 참조) ...
        else:
            adapted_prompt_template = task_prompts["memo"]
    elif task_type == "summarize":
        if content_type == "technical_explanation":
            adapted_prompt_template = "Summarize the following technical text in three sentences, focusing on the **core purpose, main methodology/process (if any), and significant results or conclusions**:\n[TEXT]"
        # ... (다른 content_type에 대한 summarize 프롬프트 생략, 기존 코드 참조) ...
        else:
            adapted_prompt_template = task_prompts["summarize"]

    user_input_en = translate_text(user_input_ko, 'auto', 'en')
    if user_input_en.startswith("Error"):
        raise Exception(f"적응형 프롬프트 사용자 입력 번역 실패: {user_input_en}")

    final_prompt_en = adapted_prompt_template.replace("[TEXT]", user_input_en)
    return final_prompt_en

# --- 핵심 실행 로직 함수 (Ollama 호출 및 번역, 기존과 동일) ---
def execute_ollama_task(english_prompt, model=DEFAULT_OLLAMA_MODEL):
    ollama_response_en = query_ollama(english_prompt, model=model)
    if ollama_response_en.startswith("Error"):
        return ollama_response_en
    ollama_response_ko = translate_text(ollama_response_en, 'auto', 'ko')
    return ollama_response_ko

# --- 2단계 실행 함수: 분류 -> 적응형 프롬프트 -> 실행 (기존과 동일) ---
def execute_adaptive_ollama_task(user_input_ko, task_type, model=DEFAULT_OLLAMA_MODEL):
    content_type = "unknown"
    try:
        print("[1단계] 내용 유형 분석 중...")
        classify_prompt_with_ko_text = task_prompts['classify'].replace("[TEXT]", user_input_ko)
        classify_prompt_en = translate_text(classify_prompt_with_ko_text, 'auto', 'en')
        if classify_prompt_en.startswith("Error"):
            print(f"  [경고] 내용 분석 프롬프트 번역 실패: {classify_prompt_en}. 기본 프롬프트를 사용합니다.")
        else:
            classification_result_en = query_ollama(classify_prompt_en, model=model)
            if classification_result_en.startswith("Error"):
                print(f"  [경고] 내용 유형 분석 실패: {classification_result_en}. 기본 프롬프트를 사용합니다.")
            else:
                detected_type = classification_result_en.splitlines()[0].strip().lower()
                expected_types = ["meeting_notes", "idea_brainstorming", "technical_explanation",
                                  "personal_reflection", "todo_list", "general_information", "other"]
                if detected_type in expected_types:
                    content_type = detected_type
                    print(f"  감지된 내용 유형: {content_type}")
                elif detected_type :
                     content_type = "other"
                     print(f"  [정보] 예상치 못한 내용 유형 응답 '{detected_type}' 감지됨. 'other'로 처리.")
                else:
                     print(f"  [경고] 내용 유형 분석 결과가 비어있거나 유효하지 않음. 기본 프롬프트를 사용합니다.")
    except Exception as e:
        print(f"  [경고] 내용 유형 분석 중 예외 발생: {type(e).__name__} - {e}. 기본 프롬프트를 사용합니다.")

    final_result_ko = f"Error: Adaptive task '{task_type}' failed before execution."
    try:
        print(f"[2단계] 내용 유형({content_type}) 기반 '{task_type}' 작업 실행 중...")
        final_english_prompt = create_adaptive_prompt(user_input_ko, task_type, content_type)
        if final_english_prompt.startswith("Error"):
            raise Exception(f"적응형 프롬프트 생성 실패: {final_english_prompt}")
        final_result_ko = execute_ollama_task(final_english_prompt, model=model)
        return final_result_ko
    except Exception as e:
        error_msg = f"적응형 작업({task_type}) 처리 중 오류 발생: {type(e).__name__} - {e}."
        print(f"  [오류] {error_msg}")
        print("[Fallback] 기본 프롬프트로 작업 재시도 중...")
        try:
            default_prompt_template_en = task_prompts[task_type]
            user_input_en = translate_text(user_input_ko, 'auto', 'en')
            if user_input_en.startswith("Error"):
                return f"오류: Fallback 시 사용자 입력 번역 실패 - {user_input_en}"
            default_prompt_en = default_prompt_template_en.replace("[TEXT]", user_input_en)
            fallback_result = execute_ollama_task(default_prompt_en, model=model)
            return fallback_result
        except Exception as fallback_e:
            return f"오류: Fallback 작업 실행 중 오류 발생 - {type(fallback_e).__name__} - {fallback_e}"

# --- Comparison 기능 함수 (기존과 동일, 로그 파일에서 'index' 작업 결과 사용) ---
def perform_comparison_task(model=DEFAULT_OLLAMA_MODEL):
    # 이 함수는 키워드 기반 비교이므로, 벡터 DB와는 직접적 관련 없음.
    # 로그 파일에서 'index' 작업 시 저장된 'output'(키워드)을 사용.
    # 만약 'index' 작업 시 키워드 저장을 중단했다면 이 함수는 수정 필요.
    # 현재는 키워드 로깅이 main 함수에서 이루어지므로 그대로 동작 가능.
    keyword_logs = []
    try:
        if not os.path.exists(LOG_FILENAME): # 일반 로그 파일 확인
            return "[오류] 로그 파일을 찾을 수 없습니다. 키워드 추출(3번) 또는 관련 작업(7번)을 먼저 수행하여 로그를 생성해주세요."

        with open(LOG_FILENAME, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    log_entry = json.loads(line)
                    # 'keyword' 작업 또는 'related_task'에서 생성된 쿼리 키워드 로그를 찾음
                    if (log_entry.get('task') == 'keyword' or \
                        (log_entry.get('task') == 'related_task_vector_rag' and 'query_keywords_ko_for_log' in log_entry)) and \
                        'output' in log_entry and \
                        isinstance(log_entry.get('output'), str) and \
                        ':' in log_entry['output'] and \
                        not log_entry['output'].startswith("Error:") and \
                        not log_entry['output'].startswith("[en]"):
                        
                        # related_task_vector_rag 인 경우, input 대신 별도 저장된 query_keywords_ko_for_log 사용
                        display_name = log_entry.get('input', 'N/A')
                        if log_entry.get('task') == 'related_task_vector_rag':
                            display_name = f"쿼리: {log_entry.get('query_keywords_ko_for_log', 'N/A')}"
                        elif log_entry.get('task') == 'keyword' and 'input' in log_entry:
                             display_name = f"텍스트: {log_entry['input'][:30]}..."


                        keyword_logs.append({
                            "timestamp": log_entry.get('timestamp', 'N/A'),
                            "name": display_name, # 표시용 이름
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

    print("\n--- 비교 가능한 키워드 로그 목록 ---")
    for i, log_data in enumerate(keyword_logs):
        print(f"{i+1}. [{log_data['timestamp']}] {log_data['name']}")
    print("----------------------------------------------")

    selected_indices = []
    # ... (사용자 선택 로직은 기존과 동일하게 유지) ...
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
        comparison_prompt_en = translate_text(comparison_prompt_ko, 'auto', 'en')
        if comparison_prompt_en.startswith("Error"):
            raise Exception(f"Comparison 프롬프트 번역 실패: {comparison_prompt_en}")

        print(f"\n[comparison] 작업을 Ollama({model})에게 요청합니다...")
        comparison_result_en = query_ollama(comparison_prompt_en, model=model)
        if comparison_result_en.startswith("Error"):
            return f"[오류] 유사성 평가 중 오류 발생: {comparison_result_en}"
        
        try:
            score_text = comparison_result_en.strip()
            match = re.search(r"(\d*\.\d+|\d+)", score_text)
            if match:
                score = float(match.group(1))
                if 0.0 <= score <= 1.0:
                    return f"'{name1}'와(과) '{name2}' 간의 키워드 기반 유사성 점수: {score:.2f}"
                else:
                    return f"계산된 유사성 점수 ({score:.2f})가 범위(0-1)를 벗어났습니다. 원본 결과: '{score_text}'"
            else:
                return f"유사성 평가 결과 (점수 추출 불가): '{score_text}'"
        except ValueError:
            return f"유사성 평가 결과 (텍스트, 점수 변환 불가): '{comparison_result_en}'"
    except Exception as e:
        return f"[오류] Comparison 작업 처리 중 문제 발생: {type(e).__name__} - {e}"

# --- 문서 관련 함수 (기존과 동일) ---
def get_document_paths(doc_dir):
    doc_path = Path(doc_dir)
    if not doc_path.is_dir():
        print(f"[오류] 문서 디렉토리 '{doc_dir}'를 찾을 수 없거나 디렉토리가 아닙니다.")
        return []
    return list(doc_path.rglob('*.md')) # 하위 디렉토리 포함

def read_document_content(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        print(f"[오류] 파일을 찾을 수 없습니다: {filepath}")
        return None
    except Exception as e:
        print(f"[오류] 파일 읽기 오류 ({filepath}): {e}")
        return None

# --- [수정됨] 문서 청킹 함수 ---
def chunk_text_by_sentences(text, sentences_per_chunk=5):
    """텍스트를 문장 단위로 청킹하는 간단한 함수 (nltk 필요 없음)"""
    if not text or not isinstance(text, str) or not text.strip():
        return []
    
    # 문장 구분자로 '.', '!', '?', '\n' 등을 고려할 수 있음
    # 좀 더 정교한 문장 분리는 nltk.sent_tokenize 등을 사용할 수 있지만, 여기서는 간단히 구현
    delimiters = ".!?\n" # 문장 구분자
    sentences = []
    current_sentence = ""
    for char in text:
        current_sentence += char
        if char in delimiters:
            if current_sentence.strip():
                sentences.append(current_sentence.strip())
            current_sentence = ""
    if current_sentence.strip(): # 마지막 문장 처리
        sentences.append(current_sentence.strip())

    if not sentences:
        return [text] # 문장 분리 안되면 원본 텍스트를 단일 청크로

    chunks = []
    current_chunk_sentences = []
    for i, sentence in enumerate(sentences):
        current_chunk_sentences.append(sentence)
        if (i + 1) % sentences_per_chunk == 0 or (i + 1) == len(sentences):
            chunks.append(" ".join(current_chunk_sentences))
            current_chunk_sentences = []
    return chunks

# --- [수정됨] 문서 인덱싱 함수 (SentenceTransformer + ChromaDB) ---
def index_documents(doc_dir):
    """
    '/Doc' 디렉토리의 .md 파일을 청킹하고, 각 청크를 영어로 번역 후
    SentenceTransformer로 임베딩하여 ChromaDB에 저장합니다.
    """
    print(f"\n--- '{doc_dir}' 내 .md 파일 벡터 인덱싱 시작 (SentenceTransformer, ChromaDB) ---")
    doc_paths = get_document_paths(doc_dir)
    if not doc_paths:
        print("인덱싱할 .md 파일이 없습니다.")
        return

    collection = initialize_chromadb() # 컬렉션 가져오기/생성
    if not collection:
        print("[오류] ChromaDB 컬렉션을 초기화할 수 없어 인덱싱을 중단합니다.")
        return

    # (선택적) 기존 로그에서 이미 처리된 파일 경로 로드 (중복 방지용 - ChromaDB ID로도 가능)
    # 여기서는 ChromaDB ID를 기준으로 중복을 피하도록 구현
    
    total_files = len(doc_paths)
    indexed_file_count = 0
    skipped_file_count = 0
    error_file_count = 0
    total_chunks_processed = 0

    for file_idx, filepath in enumerate(doc_paths, 1):
        filepath_str = str(filepath)
        print(f"\n  ({file_idx}/{total_files}) 파일 처리 중: {filepath.name}")

        # 파일 내용 읽기
        content_ko = read_document_content(filepath)
        if content_ko is None or not content_ko.strip():
            print(f"    - 내용을 읽을 수 없거나 비어있어 건너<0xEB><0x84>니다.")
            error_file_count += 1
            continue

        # 1. 내용 청킹 (한국어 기준)
        # 예시: 문장 5개씩 청킹 (청킹 전략은 내용에 따라 조절 필요)
        text_chunks_ko = chunk_text_by_sentences(content_ko, sentences_per_chunk=7)
        if not text_chunks_ko:
            print(f"    - 텍스트 청킹 결과가 없어 건너<0xEB><0x84>니다.")
            error_file_count += 1
            continue
        
        print(f"    - 원본 한국어 문서 청크 수: {len(text_chunks_ko)}")

        # 각 청크에 대한 정보 저장 리스트
        chunk_embeddings = []
        chunk_metadatas = []
        chunk_ids = []
        processed_chunks_for_this_file = 0

        for chunk_idx, chunk_ko in enumerate(text_chunks_ko):
            chunk_id_str = f"{filepath_str}_chunk_{chunk_idx}"

            # ChromaDB에서 해당 ID가 이미 있는지 확인하여 중복 방지
            # get()은 ID가 없으면 빈 리스트를 반환하므로 results['ids'] 등으로 확인
            existing_entry = collection.get(ids=[chunk_id_str])
            if existing_entry and existing_entry['ids'] and chunk_id_str in existing_entry['ids']:
                # print(f"      - 청크 ID '{chunk_id_str}'는 이미 DB에 존재하여 건너<0xEB><0x84>니다.")
                skipped_file_count += (1 if chunk_idx == 0 else 0) # 파일 단위로 스킵 카운트 (대략적)
                continue

            # 2. 한국어 청크 -> 영어로 번역
            # print(f"      - 청크 {chunk_idx + 1} 번역 중...")
            chunk_en = translate_text(chunk_ko, 'ko', 'en')
            if chunk_en.startswith("Error:") or not chunk_en.strip() :
                print(f"      - 청크 {chunk_idx + 1} 번역 실패: {chunk_en}. 이 청크는 건너<0xEB><0x84>니다.")
                continue
            
            # 3. 번역된 영어 청크 -> 임베딩 생성
            # print(f"      - 청크 {chunk_idx + 1} 임베딩 중...")
            embedding = get_embedding_for_text_en(chunk_en)
            if embedding is None:
                print(f"      - 청크 {chunk_idx + 1} 임베딩 생성 실패. 이 청크는 건너<0xEB><0x84>니다.")
                continue

            chunk_embeddings.append(embedding)
            chunk_metadatas.append({
                "source_filepath": filepath_str, # 전체 파일 경로
                "filename": filepath.name,       # 파일명
                "chunk_id_in_doc": chunk_idx,    # 문서 내 청크 순번
                "original_text_ko": chunk_ko,    # 원본 한국어 청크
                "translated_text_en": chunk_en   # 번역된 영어 청크 (임베딩 대상)
            })
            chunk_ids.append(chunk_id_str) # ChromaDB용 고유 ID
            processed_chunks_for_this_file += 1
            total_chunks_processed +=1

            # (선택적) 일정 개수마다 ChromaDB에 add (메모리 관리)
            if len(chunk_ids) >= 50: # 예: 50개 청크마다 DB에 저장
                try:
                    collection.add(embeddings=chunk_embeddings, metadatas=chunk_metadatas, ids=chunk_ids)
                    print(f"      - {len(chunk_ids)}개 청크 묶음 DB에 추가 완료.")
                    chunk_embeddings, chunk_metadatas, chunk_ids = [], [], [] # 리스트 초기화
                except Exception as db_e:
                    print(f"      - 다수 청크 DB 추가 중 오류: {db_e}")
                    # 오류 발생 시 해당 묶음은 실패 처리. 필요시 개별 재시도 로직 추가 가능

        # 파일 내 남은 청크들 저장
        if chunk_ids:
            try:
                collection.add(embeddings=chunk_embeddings, metadatas=chunk_metadatas, ids=chunk_ids)
                print(f"      - 남은 {len(chunk_ids)}개 청크 DB에 추가 완료.")
            except Exception as db_e:
                print(f"      - 파일 마지막 청크 DB 추가 중 오류: {db_e}")
        
        if processed_chunks_for_this_file > 0:
            indexed_file_count +=1
            print(f"    - 파일 '{filepath.name}'에서 {processed_chunks_for_this_file}개 청크 처리 완료.")
        elif not any(collection.get(ids=[f"{filepath_str}_chunk_{i}"])['ids'] for i in range(len(text_chunks_ko))): # 스킵도 아니고 처리된 것도 없으면 오류로 간주
            error_file_count +=1
            print(f"    - 파일 '{filepath.name}' 처리 중 유효한 청크를 DB에 저장하지 못했습니다.")


    print(f"\n--- 벡터 인덱싱 완료 ---")
    print(f"  처리 시도한 총 파일 수: {total_files}")
    print(f"  성공적으로 일부라도 인덱싱된 파일 수: {indexed_file_count}")
    print(f"  건너뛴 파일 수 (일부 청크라도 이미 존재 시): {skipped_file_count}") # 이 카운트는 정확하지 않을 수 있음
    print(f"  오류 발생 파일 수: {error_file_count}")
    print(f"  DB에 추가/확인된 총 청크 수 (대략): {collection.count()} (이번 실행에서 처리: {total_chunks_processed})")


# --- [수정됨] 벡터 기반 관련 문서 검색 함수 (SentenceTransformer + ChromaDB) ---
def find_related_documents_by_vector_similarity(query_ko, top_n=3):
    """
    한국어 쿼리를 영어로 번역 후 임베딩하여 ChromaDB에서 유사한 문서 청크를 검색.
    반환: LLM 컨텍스트로 사용될 영어 청크 텍스트 리스트와 메타데이터.
    """
    print(f"\n--- 벡터 기반 관련 문서 검색 시작 (쿼리: '{query_ko[:30]}...') ---")
    
    collection = initialize_chromadb()
    if not collection:
        print("[오류] ChromaDB 컬렉션을 초기화할 수 없어 검색을 중단합니다.")
        return []

    if not query_ko or not query_ko.strip():
        print("[오류] 검색 쿼리가 비어있습니다.")
        return []

    # 1. 한국어 쿼리 -> 영어로 번역
    query_en = translate_text(query_ko, 'ko', 'en')
    if query_en.startswith("Error:") or not query_en.strip():
        print(f"[오류] 쿼리 번역 실패: {query_en}")
        return []
    print(f"  번역된 영어 쿼리: '{query_en[:50]}...'")

    # 2. 번역된 영어 쿼리 -> 임베딩 생성
    query_embedding = get_embedding_for_text_en(query_en)
    if query_embedding is None:
        print("[오류] 쿼리 임베딩 생성에 실패했습니다.")
        return []

    # 3. 벡터 DB에서 유사도 검색
    try:
        results = collection.query(
            query_embeddings=[query_embedding], # 리스트 형태로 전달
            n_results=top_n,
            include=["metadatas", "documents", "distances"] # documents는 저장된 원본 청크 (여기서는 translated_text_en)
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
    # 'documents'는 ChromaDB에 저장 시 'documents' 파라미터로 전달한 텍스트 리스트를 의미.
    # 우리는 메타데이터에 'translated_text_en'와 'original_text_ko'를 저장했으므로 이를 활용.
    # documents_retrieved = results.get('documents')[0] if results.get('documents') else [None] * len(ids)
    distances = results.get('distances')[0]

    print(f"상위 {len(ids)}개 관련 문서 청크 정보 (벡터 유사도 기준):")
    for i in range(len(ids)):
        meta = metadatas[i]
        filename = meta.get('filename', 'N/A')
        # original_ko_chunk = meta.get('original_text_ko', '') # 원본 한국어 청크
        translated_en_chunk = meta.get('translated_text_en', '') # 번역된 영어 청크 (컨텍스트로 사용)
        distance = distances[i]

        print(f"  - {filename} (Distance: {distance:.4f})")
        # print(f"     영어 컨텍스트: {translated_en_chunk[:100]}...")

        # LLM 컨텍스트로는 번역된 영어 청크를 사용 (LLM이 영어를 더 잘 이해한다고 가정)
        retrieved_contexts.append({
            "filepath": meta.get('source_filepath', 'N/A'),
            "filename": filename,
            "context_text_en": translated_en_chunk, # 컨텍스트로 사용할 영어 텍스트
            "original_text_ko": meta.get('original_text_ko', ''), # 참고용 원본 한국어
            "score": 1 - distance # 코사인 거리 -> 유사도 (0~1, 클수록 유사)
        })
    
    # score (유사도) 기준으로 내림차순 정렬 (이미 거리순 정렬되어 있으므로 사실상 유지)
    retrieved_contexts.sort(key=lambda x: x["score"], reverse=True)
    return retrieved_contexts


# --- 메인 함수 ---
def main():
    # 스크립트 시작 시 모델 및 DB 초기화
    try:
        get_sbert_model()
        initialize_chromadb()
    except SystemExit as e: # 모델/DB 로드 실패 시 종료
        print(f"초기화 실패로 프로그램을 종료합니다: {e}")
        return
    except Exception as e:
        print(f"초기화 중 예기치 않은 오류 발생: {e}")
        traceback.print_exc()
        return


    model_to_use = DEFAULT_OLLAMA_MODEL # LLM 모델

    task_mapping = {
        '1': 'summarize', '2': 'memo', '3': 'keyword', '4': 'chat',
        '5': 'comparison', # 키워드 로그 기반 비교
        '6': 'index',      # 문서 벡터 인덱싱 (SentenceTransformer + ChromaDB)
        '7': 'related_task_vector_rag', # 벡터 RAG 기반 작업
    }

    # 로그/문서 디렉토리 생성 (이미 맨 위에서 처리)
    # try:
    #     os.makedirs(DOC_DIR, exist_ok=True)
    #     os.makedirs(LOG_DIR, exist_ok=True)
    # except OSError as e: ...

    while True:
        print("\n" + "="*10 + " 작업 선택 " + "="*10)
        print("1. 요약 (Summarize) [단일 텍스트, 최적화]")
        print("2. 메모 (Memo) [단일 텍스트, 최적화]")
        print("3. 키워드 추출 (Keyword) [단일 텍스트 대상, 결과 로깅]")
        print("4. 일반 대화 (Chat)")
        print("5. 키워드 로그 비교 (Comparison) [3번 작업 결과 활용]")
        print("--- 문서 관리 & RAG ---")
        print(f"6. 문서 벡터 인덱싱 (index) ['{DOC_DIR}' 내 .md -> 영어 번역 -> SBERT 임베딩 -> ChromaDB 저장]")
        print(f"7. 주제 관련 작업 (RAG) [벡터 DB 검색 기반, 영어 컨텍스트 활용]")
        print("exit: 종료")
        print("="*32)

        choice = input("선택: ").lower().strip()
        if choice == 'exit':
            break

        task_name = "unknown"
        result = "오류: 처리되지 않음"
        log_this_interaction = True
        user_input_for_log = "" # 로깅될 사용자 입력 (단일 작업용)
        log_metadata = {} # 추가 로깅 정보

        try:
            if choice == '5':
                task_name = "comparison"
                comparison_output = perform_comparison_task(model=model_to_use)
                print("\n" + "="*30); print(f"결과 ({task_name}):"); print(comparison_output); print("="*30 + "\n")
                log_this_interaction = False # Comparison 자체는 일반 로그에 상세히 남기지 않음

            elif choice == '6':
                task_name = "index_vector_db" # 로그용 태스크 이름 변경
                index_documents(DOC_DIR) # 인덱싱 함수는 내부적으로 메시지 출력
                log_this_interaction = False # 인덱싱 작업은 일반 로그에 남기지 않음

            elif choice == '7':
                task_name = task_mapping[choice] # related_task_vector_rag
                user_query_ko = input("질문 또는 정리할 주제를 입력하세요 (한국어): ")
                if not user_query_ko.strip():
                    print("[알림] 입력이 비어 있습니다.")
                    log_this_interaction = False
                    continue
                user_input_for_log = user_query_ko # 로깅용 사용자 입력

                # (선택적) 사용자 쿼리에서도 키워드를 뽑아 로그에 남기거나, 하이브리드 검색에 활용 가능
                # 여기서는 RAG 파이프라인에 집중
                
                # 1. 벡터 DB에서 관련 문서 청크 (영어 컨텍스트) 검색
                # top_n은 가져올 관련 청크 수
                related_contexts_info = find_related_documents_by_vector_similarity(user_query_ko, top_n=3)

                if not related_contexts_info:
                    print("[알림] 관련 문서를 찾지 못했습니다. 일반 Chat 방식으로 Fallback 합니다.")
                    task_name = "chat_fallback_after_rag_fail" # 로그용 작업명 변경
                    english_prompt_for_fallback = translate_text(user_query_ko, 'ko', 'en')
                    if english_prompt_for_fallback.startswith("Error"):
                        result = f"Fallback 프롬프트 번역 실패: {english_prompt_for_fallback}"
                        raise Exception(result)
                    result = execute_ollama_task(english_prompt_for_fallback, model=model_to_use)
                else:
                    # 2. 검색된 영어 컨텍스트를 활용하여 Ollama에 전달할 최종 프롬프트(영어) 구성
                    print("--- 관련 정보 기반 응답 생성 중 ---")
                    
                    # 컨텍스트들을 영어로 조합
                    augmented_context_en_str = ""
                    retrieved_sources_for_log = [] # 로깅용
                    for i, ctx_info in enumerate(related_contexts_info):
                        augmented_context_en_str += f"\n--- Relevant English Context {i+1} (Source: {ctx_info['filename']}) ---\n"
                        augmented_context_en_str += ctx_info['context_text_en'] + "\n"
                        retrieved_sources_for_log.append({
                            "filename": ctx_info['filename'],
                            "original_ko_chunk_preview": ctx_info['original_text_ko'][:3000] + "...",
                            "score": ctx_info['score']
                        })
                    log_metadata['retrieved_contexts'] = retrieved_sources_for_log # 로그에 추가 정보 저장

                    # 사용자 질문(한국어)을 영어로 번역
                    user_query_en = translate_text(user_query_ko, 'ko', 'en')
                    if user_query_en.startswith("Error:"):
                        result = f"사용자 질문 영어 번역 실패: {user_query_en}"
                        raise Exception(result)

                    # 최종 영어 프롬프트 구성: 영어 질문 + 영어 컨텍스트 + 영어 지시
                    final_rag_prompt_en = f""" "{user_query_en}"

Please use the following English context

{augmented_context_en_str}

"""
                    
                    print(f"  Ollama에 전달될 프롬프트 (일부): {final_rag_prompt_en[:3000]}...")
                    
                    # Ollama 실행 (영어 프롬프트 -> 영어 응답 예상) 및 결과 한국어 번역
                    # execute_ollama_task가 내부적으로 ollama_response_en -> ko 번역 수행
                    result = execute_ollama_task(final_rag_prompt_en, model=model_to_use)

            elif choice in ('1', '2', '3', '4'): # 기존 단일 입력 작업
                user_input_ko_single = input("작업할 텍스트 또는 질문을 입력하세요 (한국어): ")
                if not user_input_ko_single.strip():
                    print("[알림] 입력이 비어 있습니다.")
                    log_this_interaction = False
                    continue
                user_input_for_log = user_input_ko_single # 로깅용 입력값 저장

                if choice not in task_mapping: # 있을 수 없는 경우지만 안전장치
                    print("[오류] 내부 오류: task_mapping에 해당 선택지가 없습니다.")
                    log_this_interaction = False
                    continue
                task_name = task_mapping[choice]
                print(f"\n[{task_name}] 작업을 Ollama({model_to_use})에게 요청합니다...")

                if choice == '4': # Chat
                    english_prompt = translate_text(user_input_for_log, 'auto', 'en')
                    if english_prompt.startswith("Error"): raise Exception(english_prompt)
                    result = execute_ollama_task(english_prompt, model=model_to_use)
                elif choice in ('1', '2'): # Summarize, Memo (Adaptive)
                    result = execute_adaptive_ollama_task(user_input_for_log, task_name, model=model_to_use)
                elif choice == '3': # Keyword
                    # 키워드 프롬프트는 영어를 기반으로 하므로, [TEXT] 부분만 번역하면 됨
                    user_input_en_for_kw = translate_text(user_input_for_log, 'ko', 'en')
                    if user_input_en_for_kw.startswith("Error"):
                        raise Exception(f"키워드 추출용 입력 번역 실패: {user_input_en_for_kw}")
                    
                    keyword_prompt_template_en = task_prompts[task_name]
                    # [TEXT] 부분에 번역된 영어 사용자 입력을 삽입
                    english_prompt_for_kw = keyword_prompt_template_en.replace("[TEXT]", user_input_en_for_kw)
                    
                    keyword_result_en = query_ollama(english_prompt_for_kw, model=model_to_use)

                    if keyword_result_en.startswith("Error"):
                        result = keyword_result_en
                    else:
                        # 키워드 결과(영어) -> 한국어로 번역 (키워드 자체는 영어 유지, 점수만 있음)
                        # 프롬프트에서 키워드 자체를 영어로 생성하도록 지시했으므로,
                        # 결과 번역은 키워드 리스트 전체를 한국어로 바꾸는 것이 아니라
                        # 혹시 있을지 모를 설명부 등을 번역하거나, 원본(영어 키워드)을 그대로 사용할 수 있음
                        # 여기서는 Ollama가 영어 키워드를 생성했다고 가정하고, 그 결과를 한국어로 번역
                        # 하지만 프롬프트는 "keyword: score" 형태만 출력하라고 되어있으므로,
                        # 보통은 번역 없이 바로 사용하거나, 로깅을 위해 한국어로 한번 더 시도할 수 있음.
                        # 여기서는 사용자가 결과를 한국어로 보길 원할 수 있으므로 번역 시도.
                        keyword_result_ko = translate_text(keyword_result_en, "en", "ko")
                        result = keyword_result_ko if not keyword_result_ko.startswith("Error") else f"[en_keywords_with_error_in_ko_translation] {keyword_result_en}"
                        # 만약 'comparison' 기능에서 한국어 키워드를 사용한다면, 여기서 확실히 한국어 키워드를 확보해야 함.
                        # 현재 키워드 프롬프트는 영어로 응답 생성.
                        # 로깅 시 'output' 에 저장되는 값. comparison이 이걸 사용.
                        # Comparison은 한국어 키워드를 기대하므로, keyword_result_ko를 output으로 저장해야 함.
                        if task_name == 'keyword': # 키워드 작업의 경우
                             log_metadata['original_english_keywords'] = keyword_result_en


            else:
                print("[오류] 잘못된 선택입니다. 메뉴에 있는 번호나 'exit'를 입력해주세요.")
                log_this_interaction = False
                task_name = "invalid_choice"

            # 결과 출력 (결과를 출력해야 하는 유효 작업 완료 시)
            if task_name not in ["unknown", "invalid_choice", "index_vector_db"] and choice != '5': # comparison은 자체 출력
                print("\n" + "="*30)
                print(f"결과 ({task_name}):")
                print(result) # 최종 결과 (한국어 또는 오류 메시지)
                print("="*30 + "\n")

            # 로깅
            if log_this_interaction and isinstance(result, str) and task_name not in ["unknown", "invalid_choice"]:
                # 오류 결과도 로깅 (단, 심각한 예외로 중단된 경우는 아래 except 블록에서 처리됨)
                # if result.startswith("Error:"): print(f"[정보] 오류 결과를 로그에 기록합니다: {result[:50]}...")
                
                log_entry_data = {
                    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    "task": task_name,
                    "input": user_input_for_log,
                    "output": result, # 최종 결과 저장
                    "model_used_llm": model_to_use,
                }
                if task_name == 'related_task_vector_rag':
                    log_entry_data['sbert_model_for_rag'] = SBERT_MODEL_NAME
                if log_metadata: # 추가 메타데이터 병합
                    log_entry_data.update(log_metadata)
                
                # 'keyword' 작업이고, 'comparison'을 위해 한국어 키워드가 필요한 경우,
                # 'output' 필드에 번역된 한국어 키워드가 잘 들어가는지 확인 필요.
                # 위 keyword 처리 로직에서 result는 번역된 keyword_result_ko 이거나, 번역 실패시 영어 원본임.
                # perform_comparison_task는 output이 한국어 키워드라고 가정함.
                # 따라서 'keyword' task의 'output'은 한국어 번역된 키워드여야 함.
                if task_name == 'keyword' and 'original_english_keywords' in log_metadata:
                    # 만약 result (output)이 영어 키워드인데 comparison 위해 한국어가 필요하면 여기서 한번 더 처리?
                    # 이미 위에서 keyword_result_ko 가 result로 할당됨.
                    pass


                os.makedirs(LOG_DIR, exist_ok=True)
                with open(LOG_FILENAME, 'a', encoding='utf-8') as f:
                    f.write(json.dumps(log_entry_data, ensure_ascii=False) + '\n')

        except Exception as e: # 각 작업 루프 내에서 발생하는 주요 예외 처리
            print(f"\n[!!! 작업 '{task_name}' 처리 중 주 예외 발생 !!!]")
            print(f"오류 상세: {type(e).__name__} - {e}")
            print("--- Traceback ---")
            traceback.print_exc()
            print("--- End Traceback ---")
            print("다음 작업을 계속 진행합니다.")
            # 오류 발생 시 해당 루프의 로깅은 자동으로 건너뜀 (log_this_interaction=False 설정 또는 위에서 처리)

# --- 스크립트 실행 시작점 ---
if __name__ == "__main__":
    print(f"스크립트 시작: {datetime.datetime.now()}")
    print(f"기본 LLM 모델: {DEFAULT_OLLAMA_MODEL}")
    print(f"SentenceTransformer 임베딩 모델: {SBERT_MODEL_NAME}")
    print(f"ChromaDB 저장 경로: {CHROMA_DB_PATH}")
    print(f"로그 파일 위치: {LOG_FILENAME}")
    print(f"문서 디렉토리: {DOC_DIR}")

    # 필수 디렉토리 생성
    try:
        os.makedirs(DOC_DIR, exist_ok=True)
        os.makedirs(LOG_DIR, exist_ok=True)
        os.makedirs(CHROMA_DB_PATH, exist_ok=True) # ChromaDB 경로도 생성 확인
    except OSError as e:
        print(f"[치명적 오류] 필수 디렉토리 생성 불가: {e}. 스크립트를 종료합니다.")
        exit(1)
    
    # 메인 함수 실행 (키보드 인터럽트 처리 포함)
    try:
        main()
    except KeyboardInterrupt:
        print("\n[알림] 사용자에 의해 스크립트가 중단되었습니다.")
    except SystemExit as e: # 모델/DB 로드 실패 등 시스템 종료 예외
        print(f"프로그램 종료: {e}")
    except Exception as e: # 예상치 못한 최상위 예외
        print(f"\n[!!! 스크립트 실행 중 치명적인 오류 발생 !!!]")
        print(f"오류 상세: {type(e).__name__} - {e}")
        traceback.print_exc()
    finally:
        print(f"\n스크립트 종료: {datetime.datetime.now()}")




