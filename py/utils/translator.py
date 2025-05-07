# utils/translator.py
import time
from googletrans import Translator, LANGUAGES
from requests.exceptions import RequestException
import httpx # googletrans의 타임아웃 설정을 위해 필요할 수 있음
import traceback

from config import DEFAULT_TRANSLATION_RETRIES, DEFAULT_TRANSLATION_DELAY

# --- 번역 함수 ---
def detect_language(text):
    if not text or not isinstance(text, str) or not text.strip():
        return None
    try:
        # 매번 새로 생성하여 상태 문제 방지 시도 (googletrans==4.0.0-rc1 특정 문제 회피)
        translator = Translator()
        detected = translator.detect(text)
        return detected.lang
    except Exception as e:
        print(f"[Warning] 언어 감지 실패: {e} (텍스트: '{text[:30]}...')")
        return None

def translate_text(text, src_lang, dest_lang, retries=DEFAULT_TRANSLATION_RETRIES, delay=DEFAULT_TRANSLATION_DELAY):
    if not text or not isinstance(text, str) or not text.strip():
        return ""

    source_language = src_lang
    if source_language is None or str(source_language).lower() == 'auto':
        detected_src = detect_language(text)
        if detected_src and detected_src in LANGUAGES:
            source_language = detected_src
        else:
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
            # translator = Translator(timeout=httpx.Timeout(10.0)) # 필요시 타임아웃 설정
            translation = translator.translate(text, src=source_language, dest=dest_lang)

            if translation and hasattr(translation, 'text') and translation.text is not None:
                return translation.text
            else:
                error_msg = f"번역 결과가 예상과 다릅니다 (시도 {attempt+1}/{retries}). 입력: '{text[:50]}...', 결과: {translation}"
                print(f"[Warning] {error_msg}")

        except (RequestException, httpx.RequestError) as e:
            error_msg = f"번역 중 네트워크 오류 (시도 {attempt+1}/{retries}): {type(e).__name__} - {e}"
            print(f"[Warning] {error_msg}")
        except AttributeError as e: 
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
            
    # 루프를 모두 돌았는데도 반환되지 않은 경우 (이론상 도달 불가)
    return f"Error: 번역 루프 후 예기치 않게 실패. 입력: '{text[:50]}...'"