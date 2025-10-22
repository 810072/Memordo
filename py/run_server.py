# py/run_server.py
from waitress import serve
from app import app
from database import init_db

if __name__ == '__main__':
    print("--- Starting server script ---") #<-- 추가
    print("Initializing database...")
    try:
        init_db()
        print("Database initialization complete.") #<-- 추가
    except Exception as e:
        print(f"CRITICAL ERROR during DB init: {e}") #<-- 추가
        import traceback
        traceback.print_exc() #<-- 추가
        exit() # DB 초기화 실패 시 종료

    print("Starting Waitress server...") #<-- 추가
    try:
        serve(app, host='0.0.0.0', port=5001)
        # serve 함수가 정상 실행되면 이 아래 코드는 서버 종료 전까지 실행되지 않음
        print("--- Server stopped ---") #<-- 추가 (정상 종료 시 보임)
    except Exception as e:
        print(f"CRITICAL ERROR starting Waitress: {e}") #<-- 추가
        import traceback
        traceback.print_exc() #<-- 추가