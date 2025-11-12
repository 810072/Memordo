import torch
from transformers import AutoModelForCausalLM, AutoTokenizer 
import os
import datetime # 오늘 날짜를 동적으로 가져오기 위해 추가
from pathlib import Path # 1. 자동 경로 설정을 위해 임포트

# --- 1. 설정 및 모델 로딩 ---

# [수정 1] Path.home()을 사용하여 현재 사용자 바탕화면의 폴더 경로를 자동으로 설정
MODEL_NAME = Path.home() / "Desktop" / "Clova_test" 

print(f"로컬 경로 '{MODEL_NAME}'에서 모델을 로딩 중입니다...")

# [수정 2 & 3] device_map 제거, torch_dtype 사용, model.to("cuda") 호출
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float16, # 'dtype' 대신 'torch_dtype' 사용
    trust_remote_code=True 
    # device_map="auto" 제거
)
model.to("cuda") # 모델을 GPU(cuda)로 명시적으로 이동
print("모델을 'cuda' (GPU)로 이동 완료.")

# [수정] 불필요한 try-except 블록 제거
tokenizer = AutoTokenizer.from_pretrained(
    MODEL_NAME
)
print("토크나이저 로딩 완료.")

# 모델을 평가 모드로 설정 (메모리 사용량 최적화)
model.eval()

# --- 2. 초기 프롬프트 및 대화 기록 설정 ---

# [수정] 날짜를 동적으로 생성
today = datetime.datetime.now()
days_of_week_ko = ["월", "화", "수", "목", "금", "토", "일"]
today_str = f"- 오늘은 {today.year}년 {today.month}월 {today.day}일({days_of_week_ko[today.weekday()]})이다."

chat_history = [
    {"role": "tool_list", "content": ""},
    {"role": "system", "content": f"- AI 언어모델의 이름은 \"CLOVA X\" 이며 네이버에서 만들었다.\n{today_str}"},
]

# --- 3. 메인 질문 루프 ---
def main():
    print("-" * 40)
    print("HyperCLOVAX 단순 질문기 (로컬 모델)")
    print("종료하려면 'exit' 또는 '종료'를 입력하세요.")
    print("-" * 40)

    while True:
        try:
            user_input = input("You: ")
            if user_input.lower().strip() in ['exit', '종료']:
                print("프로그램을 종료합니다.")
                break

            # 대화 기록에 사용자 입력 추가
            chat_history.append({"role": "user", "content": user_input})

            # 채팅 템플릿 적용
            inputs = tokenizer.apply_chat_template(
                chat_history,
                add_generation_prompt=True,
                return_dict=True,
                return_tensors="pt"
            )
            
            # 입력을 모델과 동일한 장치(GPU/CPU)로 보냄
            # (model.to("cuda")로 인해 model.device가 'cuda'가 됨)
            inputs = {k: v.to(model.device) for k, v in inputs.items()}
            
            # 추론 시 그래디언트 계산 비활성화 (메모리 절약)
            with torch.no_grad():
                output_ids = model.generate(
                    **inputs,
                    max_length=2048,
                    eos_token_id=tokenizer.eos_token_id,
                    do_sample=True,
                    temperature=0.7,
                    top_p=0.9,
                )

            # 응답 디코딩 (입력 부분 제외)
            full_response = tokenizer.decode(output_ids[0], skip_special_tokens=True)
            prompt_text = tokenizer.decode(inputs["input_ids"][0], skip_special_tokens=True)
            ai_response = full_response.replace(prompt_text, "").strip()

            # 불필요한 태그 제거
            ai_response = ai_response.replace("<|endofturn|>", "").replace("<|stop|>", "").strip()

            print(f"CLOVA X: {ai_response}")

            # AI의 응답도 대화 기록에 추가 (다음 질문을 위해)
            chat_history.append({"role": "assistant", "content": ai_response})

        except KeyboardInterrupt:
            print("\n사용자에 의해 종료되었습니다.")
            break
        except Exception as e:
            print(f"오류가 발생했습니다: {e}")
            break

# 이 스크립트가 메인으로 실행될 때만 main() 함수를 호출
if __name__ == "__main__":
    main()