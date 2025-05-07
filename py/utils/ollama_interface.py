# utils/ollama_interface.py
import requests
import json
import traceback
from config import OLLAMA_API_URL, DEFAULT_OLLAMA_MODEL, OLLAMA_TIMEOUT
from utils.translator import translate_text # Ollama 결과 번역에 필요

def query_ollama(prompt, model=DEFAULT_OLLAMA_MODEL, url=OLLAMA_API_URL, timeout=OLLAMA_TIMEOUT):
    """Ollama API에 쿼리를 보내고 원시 응답 텍스트를 반환하는 함수"""
    headers = {"Content-Type": "application/json"}
    data = {"prompt": prompt, "model": model, "stream": False}
    
    try:
        response = requests.post(url, headers=headers, data=json.dumps(data), timeout=timeout)
        response.raise_for_status() # HTTP 오류 발생 시 예외 발생
        
        try:
            json_data = response.json()
        except json.JSONDecodeError as e:
            error_msg = f"Error: Ollama JSON 응답 디코딩 오류: {e}. 상태: {response.status_code}. 응답 텍스트: '{response.text[:100]}...'"
            print(f"[Error] {error_msg}")
            return error_msg # 오류 메시지 반환

        if "response" in json_data and json_data["response"] is not None:
            return json_data["response"].strip() # 앞뒤 공백 제거
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
        traceback.print_exc() # 상세 오류 내용 출력
        return error_msg

def execute_ollama_task(english_prompt, model=DEFAULT_OLLAMA_MODEL):
    """
    Ollama에 영어 프롬프트를 보내고, 응답을 한국어로 번역하여 반환합니다.
    """
    ollama_response_en = query_ollama(english_prompt, model=model)
    if ollama_response_en.startswith("Error"):
        # Ollama 쿼리 실패 시 오류 메시지 반환
        return ollama_response_en

    # Ollama 응답을 한국어로 번역 ('auto' 감지 시도, 보통 영어일 것)
    ollama_response_ko = translate_text(ollama_response_en, 'auto', 'ko')
    # 번역 결과 반환 (성공 또는 번역 오류 메시지)
    return ollama_response_ko