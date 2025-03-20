from googletrans import Translator
import requests
import json

def translate_text(text, src_lang, dest_lang):
    """텍스트 번역 함수 (googletrans 사용)"""
    translator = Translator()
    translated = translator.translate(text, src=src_lang, dest=dest_lang)
    return translated.text

def query_ollama(prompt, model="qwen2.5"):
    """Ollama API에 쿼리를 보내는 함수"""
    url = "http://localhost:11434/api/generate"
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
           return "Error: 'response' key not found in Ollama output."

    except requests.exceptions.RequestException as e:
        return f"Error querying Ollama: {e}"
    except (KeyError, json.JSONDecodeError) as e:
       return f"Error processing Ollama response: {type(e).__name__} - {e}"


def main():
    """메인 함수: 사용자 입력, 번역, Ollama 쿼리, 결과 출력"""

    while True:
        korean_prompt = input("한국어 프롬프트를 입력하세요 (종료하려면 'exit' 입력): ")
        if korean_prompt.lower() == 'exit':
            break

        # 1. 한국어 -> 영어 번역
        english_prompt = translate_text(korean_prompt, "ko", "en")
        print(f"Translated to English: {english_prompt}\n")

        # 2. Ollama에 쿼리
        ollama_response = query_ollama(english_prompt)
        print(f"Ollama Response (English): {ollama_response}\n")

        # 3. 영어 -> 한국어 번역
        korean_response = translate_text(ollama_response, "en", "ko")
        print(f"Ollama Response (Korean): {korean_response}\n")

if __name__ == "__main__":
    main()