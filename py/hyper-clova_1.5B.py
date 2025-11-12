import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
import os
import datetime
from pathlib import Path

# --- 1. 모델 및 토크나이저 로딩 함수 ---

def load_clova_model():
    """
    Clova 모델과 토크나이저를 로드하고 GPU로 이동시킨 후 반환합니다.
    """
    MODEL_NAME = Path.home() / "Desktop" / "Clova_test"

    print(f"로컬 경로 '{MODEL_NAME}'에서 Clova 모델을 로딩 중입니다...")

    model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        torch_dtype=torch.float16,
        trust_remote_code=True
    )
    model.to("cuda")
    model.eval() # 평가 모드로 설정
    print("Clova 모델을 'cuda' (GPU)로 이동 및 평가 모드로 설정 완료.")

    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    print("Clova 토크나이저 로딩 완료.")

    return model, tokenizer

# --- 2. 텍스트 생성 함수 ---

def generate_clova_response(model, tokenizer, prompt_text: str) -> str:
    """
    주어진 프롬프트를 기반으로 Clova 모델의 응답을 생성합니다.
    이 함수는 RAG 워크플로우와 같이 단일 요청-응답에 적합합니다.
    """
    # RAG에서는 대화 기록이 필요 없으므로, 간단한 시스템 프롬프트만 사용
    chat_history = [
        {"role": "system", "content": "- AI 언어모델의 이름은 \"CLOVA X\" 이며 네이버에서 만들었다."},
        {"role": "user", "content": prompt_text}
    ]

    inputs = tokenizer.apply_chat_template(
        chat_history,
        add_generation_prompt=True,
        return_dict=True,
        return_tensors="pt"
    )

    inputs = {k: v.to(model.device) for k, v in inputs.items()}

    with torch.no_grad():
        output_ids = model.generate(
            **inputs,
            max_length=2048,
            eos_token_id=tokenizer.eos_token_id,
            do_sample=True,
            temperature=0.7,
            top_p=0.9,
        )

    full_response = tokenizer.decode(output_ids[0], skip_special_tokens=True)

    # 입력 프롬프트 부분을 응답에서 제거
    # apply_chat_template이 생성하는 전체 텍스트를 기반으로 응답만 분리
    templated_prompt = tokenizer.decode(inputs["input_ids"][0], skip_special_tokens=True)
    ai_response = full_response.replace(templated_prompt, "").strip()

    # 불필요한 태그 제거
    ai_response = ai_response.replace("<|endofturn|>", "").replace("<|stop|>", "").strip()

    return ai_response

# --- 3. 기존의 독립 실행 기능 (테스트용) ---

def main():
    """
    이 스크립트를 직접 실행할 때 사용되는 대화형 테스트 함수입니다.
    """
    print("-" * 40)
    print("HyperCLOVAX 단순 질문기 (로컬 모델)")
    print("종료하려면 'exit' 또는 '종료'를 입력하세요.")
    print("-" * 40)

    # 모델 로딩
    model, tokenizer = load_clova_model()

    # 동적인 날짜 정보가 포함된 대화 기록 (테스트용)
    today = datetime.datetime.now()
    days_of_week_ko = ["월", "화", "수", "목", "금", "토", "일"]
    today_str = f"- 오늘은 {today.year}년 {today.month}월 {today.day}일({days_of_week_ko[today.weekday()]})이다."

    chat_history_for_main = [
        {"role": "tool_list", "content": ""},
        {"role": "system", "content": f"- AI 언어모델의 이름은 \"CLOVA X\" 이며 네이버에서 만들었다.\n{today_str}"},
    ]

    while True:
        try:
            user_input = input("You: ")
            if user_input.lower().strip() in ['exit', '종료']:
                print("프로그램을 종료합니다.")
                break

            chat_history_for_main.append({"role": "user", "content": user_input})

            inputs = tokenizer.apply_chat_template(
                chat_history_for_main,
                add_generation_prompt=True,
                return_dict=True,
                return_tensors="pt"
            )
            
            inputs = {k: v.to(model.device) for k, v in inputs.items()}
            
            with torch.no_grad():
                output_ids = model.generate(
                    **inputs,
                    max_length=2048,
                    eos_token_id=tokenizer.eos_token_id,
                    do_sample=True,
                    temperature=0.7,
                    top_p=0.9,
                )

            full_response = tokenizer.decode(output_ids[0], skip_special_tokens=True)
            prompt_text = tokenizer.decode(inputs["input_ids"][0], skip_special_tokens=True)
            ai_response = full_response.replace(prompt_text, "").strip()
            ai_response = ai_response.replace("<|endofturn|>", "").replace("<|stop|>", "").strip()

            print(f"CLOVA X: {ai_response}")

            chat_history_for_main.append({"role": "assistant", "content": ai_response})

        except KeyboardInterrupt:
            print("\n사용자에 의해 종료되었습니다.")
            break
        except Exception as e:
            print(f"오류가 발생했습니다: {e}")
            break

if __name__ == "__main__":
    main()
