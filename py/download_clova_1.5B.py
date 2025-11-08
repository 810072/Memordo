from huggingface_hub import snapshot_download
import os

# 다운로드할 모델 이름
model_id = "naver-hyperclovax/HyperCLOVAX-SEED-Text-Instruct-1.5B"

# 모델을 저장할 로컬 폴더 경로
save_directory = r"C:\Users\pc\Desktop\Clova_test" # 삭제했던 그 경로

# 폴더가 없으면 생성
if not os.path.exists(save_directory):
    os.makedirs(save_directory)

print(f"'{model_id}' 모델을 '{save_directory}' 폴더로 다운로드합니다...")

# 저장소의 모든 파일을 다운로드
snapshot_download(
    repo_id=model_id,
    local_dir=save_directory,
    local_dir_use_symlinks=False, # Windows에서는 False가 안전합니다.
    
    # [수정된 부분]
    # 다운로드할 파일 패턴을 명시적으로 지정합니다.
    allow_patterns=[
        "*.json",
        "*.safetensors",
        "*.py",  # <--- 커스텀 코드 파일
        "*.md",
        "LICENSE",
        ".gitattributes"
    ]
)

print("다운로드 완료!")