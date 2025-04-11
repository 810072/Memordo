# markdown_memo.py
import os
import datetime

# --- 설정 ---
MEMO_DIRECTORY = "memos" # 메모를 저장할 기본 디렉토리

# --- 내부 헬퍼 함수 ---
def _ensure_dir(directory):
    """지정된 디렉토리가 없으면 생성합니다."""
    if not os.path.exists(directory):
        os.makedirs(directory)
        print(f"디렉토리 생성: {directory}")

def _generate_filename():
    """메모 파일 이름을 생성합니다 (타임스탬프 기반)."""
    now = datetime.datetime.now()
    return now.strftime("%Y%m%d_%H%M%S") + ".md"

# --- 핵심 기능 함수 ---

def save_memo(content, directory=MEMO_DIRECTORY):
    """
    메모 내용을 Markdown 파일로 저장합니다.

    Args:
        content (str): 저장할 메모 내용.
        directory (str, optional): 메모를 저장할 디렉토리. 기본값은 MEMO_DIRECTORY.

    Returns:
        str: 저장된 파일의 전체 경로. None이면 저장 실패.
    """
    _ensure_dir(directory)
    filename = _generate_filename()
    filepath = os.path.join(directory, filename)

    try:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"메모 저장 완료: {filepath}")
        return filepath
    except IOError as e:
        print(f"오류: 메모 저장 실패 - {e}")
        return None

def list_memos(directory=MEMO_DIRECTORY):
    """
    지정된 디렉토리의 메모 파일 목록을 반환합니다.

    Args:
        directory (str, optional): 메모 파일이 있는 디렉토리. 기본값은 MEMO_DIRECTORY.

    Returns:
        list: Markdown 메모 파일 이름 목록. 디렉토리가 없으면 빈 리스트.
    """
    if not os.path.exists(directory):
        print(f"경고: 디렉토리가 존재하지 않습니다 - {directory}")
        return []

    try:
        files = [f for f in os.listdir(directory) if f.endswith('.md')]
        return sorted(files, reverse=True) # 최신 메모가 위로 오도록 정렬
    except OSError as e:
        print(f"오류: 메모 목록 읽기 실패 - {e}")
        return []

def get_memo_content(filename, directory=MEMO_DIRECTORY):
    """
    지정된 메모 파일의 내용을 읽어 반환합니다. ('전달' 기능에 해당)

    Args:
        filename (str): 읽어올 메모 파일 이름 (확장자 포함).
        directory (str, optional): 메모 파일이 있는 디렉토리. 기본값은 MEMO_DIRECTORY.

    Returns:
        str: 파일 내용. 파일을 읽을 수 없으면 None.
    """
    filepath = os.path.join(directory, filename)
    if not os.path.exists(filepath):
        print(f"오류: 파일을 찾을 수 없습니다 - {filepath}")
        return None

    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        return content
    except IOError as e:
        print(f"오류: 메모 읽기 실패 - {e}")
        return None

def display_memo(filename, directory=MEMO_DIRECTORY):
    """
    지정된 메모 파일의 내용을 화면에 출력합니다. ('출력' 기능)

    Args:
        filename (str): 표시할 메모 파일 이름.
        directory (str, optional): 메모 파일이 있는 디렉토리. 기본값은 MEMO_DIRECTORY.
    """
    content = get_memo_content(filename, directory)
    if content is not None:
        print(f"\n--- 메모 내용 ({filename}) ---")
        print(content)
        print("---------------------------\n")
    # get_memo_content 내부에서 오류 메시지 출력하므로 별도 처리는 생략

def input_memo():
    """
    사용자로부터 여러 줄의 메모 입력을 받습니다. ('입력' 기능)
    입력 종료는 새 줄에 'EOF' 또는 Ctrl+D(Linux/macOS)/Ctrl+Z+Enter(Windows) 입력.

    Returns:
        str: 사용자가 입력한 전체 메모 내용.
    """
    print("메모 내용을 입력하세요. 입력을 마치려면 새 줄에 EOF를 입력하거나 Ctrl+D(Ctrl+Z+Enter)를 누르세요.")
    lines = []
    while True:
        try:
            line = input()
            if line.strip().upper() == "EOF": # EOF 입력 시 종료
                break
            lines.append(line)
        except EOFError: # Ctrl+D 또는 Ctrl+Z+Enter 입력 시 종료
            break
    return "\n".join(lines)

# --- (선택) 모듈 직접 실행 시 예제 코드 ---
if __name__ == "__main__":
    print("Markdown 메모 모듈 테스트")

    # 1. 메모 입력 받기
    memo_text = input_memo()

    if memo_text:
        # 2. 메모 저장
        saved_path = save_memo(memo_text)

        if saved_path:
            # 3. 메모 목록 보기
            print("\n--- 저장된 메모 목록 ---")
            memo_list = list_memos()
            if memo_list:
                for i, fname in enumerate(memo_list):
                    print(f"{i+1}. {fname}")

                # 4. 가장 최근 메모 내용 가져오기 ('전달') 및 출력 ('출력')
                latest_memo_filename = memo_list[0]
                print(f"\n가장 최근 메모 '{latest_memo_filename}' 표시:")
                display_memo(latest_memo_filename)

                # 특정 메모 내용 가져오기 (변수에 저장)
                retrieved_content = get_memo_content(latest_memo_filename)
                if retrieved_content:
                     print(f"\n'{latest_memo_filename}' 내용 가져오기 성공 (첫 30자): {retrieved_content[:30]}...")

            else:
                print("저장된 메모가 없습니다.")
    else:
        print("입력된 내용이 없어 메모를 저장하지 않았습니다.")