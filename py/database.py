# py/database.py
import sqlite3
import os
import traceback # 오류 로깅

# 현재 파일 위치 기준 DB 경로 설정
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, 'memordo_data.db') # DB 파일 이름

def init_db():
    """데이터베이스 파일과 방문 기록 테이블을 초기화합니다."""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # 방문 기록 테이블 (visit_history) 생성
        # user_email은 사용자별 데이터 구분을 위함 (추후 인증 구현 시 필수)
        # UNIQUE 제약 조건으로 (url, timestamp, user_email) 조합의 중복 삽입 방지
        cursor.execute('''
        CREATE TABLE IF NOT EXISTS visit_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            title TEXT,
            timestamp TEXT NOT NULL,
            user_email TEXT NOT NULL,
            UNIQUE(url, timestamp, user_email)
        )
        ''')
        print("Table 'visit_history' initialized.")

        # 필요하다면 다른 테이블 생성 로직 추가 가능

        conn.commit()
        conn.close()
        print(f"Database initialized successfully at {DB_PATH}")
    except Exception as e:
        print(f"CRITICAL - Database initialization failed: {e}")
        traceback.print_exc()
        raise SystemExit("Database initialization failed")


def get_db_connection():
    """데이터베이스 연결 객체를 반환 (결과를 딕셔너리처럼 사용 가능하게 설정)."""
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row # 결과를 dict 형태로 받기 위함
        return conn
    except Exception as e:
        print(f"Error getting DB connection: {e}")
        traceback.print_exc()
        return None

# 직접 실행 시 DB 초기화 (테스트용)
if __name__ == '__main__':
    print("Initializing database directly...")
    init_db()