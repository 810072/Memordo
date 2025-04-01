import json
import datetime
import time
import requests
import os
from googletrans import Translator # googletrans 사용 시 필요
from requests.exceptions import RequestException



OLLAMA_API_URL = "http://localhost:11434/api/generate"
DEFAULT_OLLAMA_MODEL = "mistral:7b"
LOG_DIR = "log"
LOG_FILENAME = os.path.join(LOG_DIR, "interaction_log.jsonl")

# --- 번역 함수 ---
def translate_text(text, src_lang, dest_lang, retries=3, delay=1):
    """텍스트 번역 함수 (googletrans 사용, 재시도 추가)"""
    for attempt in range(retries):
        try:
            translator = Translator()
            # 타임아웃 설정 추가 가능 (선택 사항)
            # translator = Translator(timeout=httpx.Timeout(10.0))
            translation = translator.translate(text, src=src_lang, dest=dest_lang)
            if translation and hasattr(translation, 'text'):
                return translation.text
            else:
                # 번역 객체는 있으나 text 속성이 없는 경우 등
                error_msg = f"Translation failed (attempt {attempt+1}/{retries}). Input: '{text[:50]}...', Src: {src_lang}, Dest: {dest_lang}"
                print(f"[Warning] {error_msg}") # 로그 대신 간단히 출력
        except RequestException as e: # requests 관련 네트워크 오류
            error_msg = f"Network error during translation (attempt {attempt+1}/{retries}): {type(e).__name__} - {e}"
            print(f"[Warning] {error_msg}")
        except Exception as e: # 그 외 googletrans 내부 오류 등
             # googletrans의 특정 오류 타입 확인 필요 (예: AttributeError, JSONDecodeError 등)
            error_msg = f"Error during translation (attempt {attempt+1}/{retries}): {type(e).__name__} - {e}"
            print(f"[Warning] {error_msg}")

        if attempt < retries - 1:
            time.sleep(delay * (2 ** attempt)) # Exponential backoff
        else:
            # 최종 실패
            return f"Error: Translation failed after {retries} attempts. Input: '{text[:50]}...'"
    return f"Error: Translation failed unexpectedly. Input: '{text[:50]}...'" # 루프 후 반환 (이론상 도달 안 함)


# --- Ollama 쿼리 함수 ---
def query_ollama(prompt, model=DEFAULT_OLLAMA_MODEL, url=OLLAMA_API_URL):
    """Ollama API에 쿼리를 보내는 함수"""
    headers = {"Content-Type": "application/json"}
    data = {
        "prompt": prompt,
        "model": model,
        "stream": False,
    }
    try:
        response = requests.post(url, headers=headers, data=json.dumps(data))
        response.raise_for_status()
        json_data = response.json()
        if "response" in json_data:
            return json_data["response"]
        else:
            error_msg = json_data.get("error", "Unknown error format from Ollama.")
            return f"Error: 'response' key not found. Ollama returned: {error_msg}"
    except requests.exceptions.RequestException as e:
        return f"Error querying Ollama: {e}"
    except json.JSONDecodeError as e:
        return f"Error decoding Ollama response: {e}. Response text: '{response.text[:100]}...'"
    except Exception as e:
        return f"An unexpected error occurred in query_ollama: {type(e).__name__} - {e}"


# --- 작업별 프롬프트 템플릿 ---
# (이전과 동일)
task_prompts = {
    "summarize": "다음 텍스트를 세 문장으로 요약해 주세요. 주요 내용을 포함해야 합니다:\n[TEXT]",
    "memo": "다음 내용을 바탕으로 주요 아이디어와 결정 사항을 글머리 기호(bullet point)를 사용하여 메모해 주세요:\n[TEXT]",
    "keyword": """다음 텍스트에서 가장 중요한 키워드를 10개 가량 식별하고, 각 키워드가 텍스트 전체 내용에서 차지하는 중요도(지분)를 0에서 1 사이의 점수로 추정해주세요.
점수가 가장 높은 상위 5개의 키워드와 해당 점수를 다음 형식으로만 나열해주세요:
키워드1: 점수1
키워드2: 점수2
키워드3: 점수3
키워드4: 점수4
키워드5: 점수5

[TEXT]""",
    "comparison": """다음은 두 텍스트에서 추출된 주요 키워드와 그 중요도 점수 목록입니다. 이 두 키워드 목록 간의 주제적 유사성을 평가하고, 0 (유사성 없음)에서 1 (매우 높은 유사성) 사이의 점수를 부여해주세요. 소수점 둘째 자리까지의 점수만 간결하게 출력해주세요.

목록 1:
[KEYWORDS1]

목록 2:
[KEYWORDS2]"""
}

# --- 작업 프롬프트 생성 함수 ---
# (이전과 동일 - 생략)
def create_task_prompt(user_input_ko, task_type):
    """주어진 작업 유형과 사용자 입력을 기반으로 프롬프트를 생성하고 번역 (단일 텍스트용)"""
    if task_type not in task_prompts:
        raise ValueError(f"Invalid or unsupported task type for single input: {task_type}")
    if task_type == "comparison":
         raise ValueError("'comparison' task requires a different prompt creation logic.")

    korean_prompt = task_prompts[task_type].replace("[TEXT]", user_input_ko)
    english_prompt = translate_text(korean_prompt, "ko", "en")
    if english_prompt.startswith("Error"):
        raise Exception(f"Failed to translate task prompt: {english_prompt}")
    return english_prompt

# --- 핵심 실행 로직 함수 (Ollama 호출 및 번역) ---
# (이전과 동일 - 생략)
def execute_ollama_task(english_prompt, model=DEFAULT_OLLAMA_MODEL):
    """Ollama에 영어 프롬프트를 보내고, 응답을 한국어로 번역하여 반환"""
    ollama_response_en = query_ollama(english_prompt, model=model)
    if ollama_response_en.startswith("Error"):
        return ollama_response_en
    ollama_response_ko = translate_text(ollama_response_en, "en", "ko")
    return ollama_response_ko


# --- <<< Comparison 기능 구현 함수 (사용자 선택 방식) >>> ---
def perform_comparison_task():
    """로그 파일에서 keyword 결과를 보여주고 사용자가 선택한 2개의 유사성 점수를 계산"""
    keyword_logs = []
    try:
        # 로그 파일 읽기
        with open(LOG_FILENAME, 'r', encoding='utf-8') as f:
            for line in f:
                try:
                    log_entry = json.loads(line)
                    if log_entry.get('task') == 'keyword' and 'output' in log_entry and 'input' in log_entry:
                         # 필요한 정보(타임스탬프, 입력, 출력) 포함하여 저장
                        keyword_logs.append({
                            "timestamp": log_entry.get('timestamp', 'N/A'),
                            "input_snippet": log_entry['input'][:30] + ('...' if len(log_entry['input']) > 30 else ''), # 입력 내용 일부
                            "output": log_entry['output']
                        })
                except json.JSONDecodeError:
                    print(f"[경고] 로그 파일 '{LOG_FILENAME}'의 일부 라인 파싱 실패. 건너<0xEB><0x84>니다.")
                    continue

    except FileNotFoundError:
        return "[오류] 로그 파일을 찾을 수 없습니다. 'keyword' 작업을 먼저 수행해주세요."

    if len(keyword_logs) < 2:
        return f"[오류] 비교할 'keyword' 작업 결과가 로그에 2개 이상 필요합니다. 현재 {len(keyword_logs)}개 있습니다."

    # --- 사용자에게 목록 보여주기 ---
    print("\n--- 비교 가능한 '키워드 추출' 로그 목록 ---")
    for i, log_data in enumerate(keyword_logs):
        print(f"{i+1}. [{log_data['timestamp']}] Input: \"{log_data['input_snippet']}\"")
    print("-----------------------------------------")

    # --- 사용자로부터 두 개의 로그 번호 입력받기 ---
    selected_indices = []
    while len(selected_indices) < 2:
        try:
            if not selected_indices: # 첫 번째 번호 요청
                 prompt_msg = "비교할 첫 번째 로그 번호를 입력하세요: "
            else: # 두 번째 번호 요청
                 prompt_msg = "비교할 두 번째 로그 번호를 입력하세요: "

            choice_str = input(prompt_msg).strip()
            choice_num = int(choice_str)

            if 1 <= choice_num <= len(keyword_logs):
                selected_index = choice_num - 1
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

    keywords1_str = log1['output']
    keywords2_str = log2['output']
    timestamp1 = log1.get('timestamp', 'N/A')
    timestamp2 = log2.get('timestamp', 'N/A')

    print(f"\n--- 선택된 비교 대상 ---")
    print(f"1: [{timestamp1}] Input: \"{log1['input_snippet']}\"")
    print(f"2: [{timestamp2}] Input: \"{log2['input_snippet']}\"")
    # print(f"   Keywords:\n{keywords1_str}") # 필요 시 키워드 내용도 출력
    # print(f"   Keywords:\n{keywords2_str}")
    print("-------------------------")

    # --- Ollama 비교 요청 ---
    try:
        korean_prompt = task_prompts["comparison"]
        korean_prompt = korean_prompt.replace("[KEYWORDS1]", keywords1_str)
        korean_prompt = korean_prompt.replace("[KEYWORDS2]", keywords2_str)

        english_prompt = translate_text(korean_prompt, "ko", "en")
        if english_prompt.startswith("Error"):
            raise Exception(f"Comparison 프롬프트 번역 실패: {english_prompt}")

        print(f"\n[comparison] 작업을 Ollama({DEFAULT_OLLAMA_MODEL})에게 요청합니다...")
        comparison_result = execute_ollama_task(english_prompt, model=DEFAULT_OLLAMA_MODEL)

        try:
             score_text = comparison_result.strip().replace(',', '.') # 쉼표를 점으로 변경
             score = float(score_text)
             return f"선택된 두 로그 간의 유사성 점수: {score:.2f}"
        except ValueError:
             return f"유사성 평가 결과 (텍스트): {comparison_result}" # 점수 변환 실패 시

    except Exception as e:
        return f"[오류] Comparison 작업 처리 중 문제 발생: {e}"


# --- 메인 함수 ---
def main():
    """메인 함수: 사용자 입력, 작업 선택, Ollama 쿼리, 결과 출력 및 로깅"""
    model_to_use = DEFAULT_OLLAMA_MODEL

    task_mapping = {
        '1': 'summarize',
        '2': 'memo',
        '3': 'keyword',
        '5': 'comparison'
    }

    try:
        os.makedirs(LOG_DIR, exist_ok=True)
    except OSError as e:
        print(f"[오류] 로그 디렉토리 '{LOG_DIR}' 생성 실패: {e}")
        return

    while True:
        print("\n수행할 작업을 선택하세요:")
        print("1. 요약 (summarize)")
        print("2. 메모 (memo)")
        print("3. 키워드 추출 (keyword)")
        print("4. 일반 대화 (chat)")
        print("5. 관계성 평가 (comparison) [로그 선택 방식]") # 설명 수정
        print("exit: 종료")

        choice = input("선택: ").lower()
        if choice == 'exit':
            break

        if choice == '5': # Comparison 작업
            comparison_output = perform_comparison_task()
            print("\n" + "="*30)
            print(f"결과 (comparison):")
            print(comparison_output)
            print("="*30 + "\n")

        elif choice in ('1', '2', '3', '4'): # 단일 입력 작업 또는 채팅
            # (이전 코드와 동일 - 입력받고, 프롬프트 만들고, 실행하고, 로깅)
            user_input_ko = input("작업할 텍스트 또는 질문을 입력하세요: ")
            if not user_input_ko.strip():
                print("입력이 비어 있습니다. 다시 입력해주세요.")
                continue

            english_prompt = None
            task_name = "알 수 없는 작업"

            try:
                if choice == '4': # 일반 대화
                    task_name = "chat"
                    english_prompt = translate_text(user_input_ko, 'ko', 'en')
                    if english_prompt.startswith("Error"):
                         raise Exception(f"일반 대화 입력 번역 실패: {english_prompt}")

                elif choice in task_mapping: # 정의된 작업 (1, 2, 3)
                    task_type = task_mapping[choice]
                    task_name = task_type
                    english_prompt = create_task_prompt(user_input_ko, task_type)

                else:
                    print(f"오류: 내부 로직 오류. 선택({choice}) 처리 불가.")
                    continue

                print(f"\n[{task_name}] 작업을 Ollama({model_to_use})에게 요청합니다...")
                result = execute_ollama_task(english_prompt, model=model_to_use)

                print("\n" + "="*30)
                print(f"결과 ({task_name}):")
                print(result)
                print("="*30 + "\n")

                if not result.startswith("Error"):
                    try:
                        log_entry = {
                            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                            "task": task_name,
                            "input": user_input_ko,
                            "output": result
                        }
                        os.makedirs(LOG_DIR, exist_ok=True)
                        with open(LOG_FILENAME, 'a', encoding='utf-8') as f:
                            f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')
                    except Exception as log_e:
                        print(f"[오류] 로그 파일 '{LOG_FILENAME}'에 저장 중 문제 발생: {log_e}")

            except ValueError as e:
                print(f"작업 준비 중 오류: {e}")
            except Exception as e:
                print(f"[{task_name}] 처리 중 오류 발생: {e}")

        else: # 잘못된 선택
            print("잘못된 선택입니다. 메뉴에 있는 번호나 exit를 입력해주세요.")

if __name__ == "__main__":
    print(f"스크립트 시작: {datetime.datetime.now()}")
    try:
        main()
    finally:
        print(f"스크립트 종료: {datetime.datetime.now()}")