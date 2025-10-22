# py/app.py

from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
import traceback
import datetime
import os
import json
import asyncio
import sqlite3 # <--- 추가
import pandas as pd # <--- 추가
import uuid # 임시 토큰 생성용 (실제로는 JWT 라이브러리 사용)
from urllib.parse import urlparse # <--- 추가

# --- DB 임포트 ---
from database import get_db_connection # <--- 추가

# --- 1. 초기 설정 (수정됨) ---
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "log")

# --- 2. AI 모듈 및 워크플로우 임포트 (수정됨) ---
try:
    from gemini_ai import initialize_ai_client, get_embedding_for_text, get_embeddings_batch, query_gemini, query_gemini_with_history, execute_simple_task, DEFAULT_GEMINI_MODEL
    print("'gemini_ai.py' 모듈 로드 성공.")
    
    from rag_workflow import build_rag_workflow
    print("'rag_workflow.py' 모듈 로드 성공.")
    
except ImportError as e:
    print(f"CRITICAL - 모듈 import 실패: {e}")
    exit(1)

# --- 3. Flask 앱 설정 ---
app = Flask(__name__)
CORS(app)

# --- 4. 유틸리티 함수: 로깅 (변경 없음) ---
def log_api_interaction(log_data):
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        api_log_filename = os.path.join(LOG_DIR, "api_interaction_log.jsonl")
        with open(api_log_filename, 'a', encoding='utf-8') as f:
            f.write(json.dumps(log_data, ensure_ascii=False) + '\n')
    except Exception as e:
        print(f"API 로깅 실패: {e}")

# --- 5. API 엔드포인트 정의 ---
@app.route('/')
def home():
    return jsonify({"message": "Gemini AI Python 백엔드 서버가 실행 중입니다.", "status": "ok"})

@app.route('/api/initialize', methods=['POST'])
def initialize_ai():
    data = request.json
    api_key = data.get('api_key')
    
    if not api_key:
        return jsonify({'error': 'api_key가 필요합니다.'}), 400
    
    os.environ['GOOGLE_API_KEY'] = api_key
        
    success = initialize_ai_client(api_key)
    
    if success:
        return jsonify({'message': 'AI 클라이언트가 성공적으로 초기화되었습니다.'}), 200
    else:
        return jsonify({'error': 'AI 클라이언트 초기화에 실패했습니다.'}), 500

@app.route('/api/rag_chat', methods=['POST'])
def rag_chat():
    data = request.json
    if not data or 'query' not in data or 'notes' not in data or 'edges' not in data:
        return jsonify({'error': '잘못된 요청. query, notes, edges가 필요합니다.'}), 400

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    
    result = {}

    try:
        rag_app = build_rag_workflow()
        
        # ✨ messages(대화 기록) 추출
        messages = data.get('messages', [])
        
        inputs = {
            "question": data['query'],
            "notes": data['notes'],
            "edges": data['edges'],
            "messages": messages,  # ✨ 대화 기록 추가
        }
        result = rag_app.invoke(inputs)
        
        log_api_interaction({
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/rag_chat",
            "input_query": data['query'],
            "output_answer": result.get('answer', 'N/A'),
            "final_context": result.get('final_context', 'N/A')
        })
        
        return jsonify({
            'result': result.get('answer'),
            'sources': result.get('sources')
        })
        
    except Exception as e:
        if "AI client has not been initialized" in str(e):
              print(f"API /rag_chat 처리 중 오류: AI 클라이언트가 초기화되지 않았습니다.")
              return jsonify({"error": "AI가 초기화되지 않았습니다. 먼저 API 키를 등록해주세요."}), 503
        
        print(f"API /rag_chat 처리 중 예외: {e}")
        traceback.print_exc()
        log_api_interaction({
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/rag_chat",
            "error": str(e),
            "traceback": traceback.format_exc()
        })
        return jsonify({"error": "서버 내부 오류 발생"}), 500
    finally:
        loop.close()

@app.route('/api/get-embeddings', methods=['POST'])
def get_embeddings():
    try:
        notes_data = request.get_json()
        if not notes_data or not isinstance(notes_data, list):
            return jsonify({"error": "잘못된 형식의 데이터입니다."}), 400
        contents = [note.get('content', '') for note in notes_data]
        file_names = [note.get('fileName', '') for note in notes_data]
        vectors = get_embeddings_batch(contents)
        embeddings_map = {
            file_names[i]: vectors[i]
            for i in range(len(file_names)) if vectors[i]
        }
        return jsonify(embeddings_map)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/execute_task', methods=['POST'])
def api_execute_task():
    try:
        data = request.get_json()
        task_type = data.get('task_type')
        user_input_ko = data.get('text')
        messages = data.get('messages', [])  # ✨ 대화 기록 추출
        
        if not task_type or user_input_ko is None:
            return jsonify({"error": "필수 파라미터 누락"}), 400
        
        if task_type == 'chat':
            # ✨ 대화 기록이 있으면 query_gemini_with_history 사용
            if messages:
                result_text = query_gemini_with_history(user_input_ko, messages)
            else:
                result_text = query_gemini(user_input_ko)
        elif task_type in ['summarize', 'memo', 'keyword']:
            result_text = execute_simple_task(task_type, user_input_ko)
        else:
            return jsonify({"error": f"지원하지 않는 task_type: {task_type}"}), 400
        
        return jsonify({"result": result_text})
    except Exception as e:
        import traceback
        print(f"'/api/execute_task'에서 에러 발생: {e}")
        traceback.print_exc()
        return jsonify({"error": "서버 내부 오류 발생"}), 500

@app.route('/api/generate-graph-data', methods=['POST'])
def generate_graph_data():
    try:
        notes_data = request.get_json()
        if not notes_data: return jsonify({"error": "데이터 없음"}), 400
        embeddings = {}
        for note in notes_data:
            file_name, content = note.get('fileName'), note.get('content')
            if file_name and content:
                vector = get_embedding_for_text(content)
                if vector: embeddings[file_name] = vector
        if not embeddings: return jsonify({"nodes": [], "edges": []})
        nodes = [{"id": fn} for fn in embeddings.keys()]
        edges = []
        file_names = list(embeddings.keys())
        for i in range(len(file_names)):
            for j in range(i + 1, len(file_names)):
                v_a, v_b = np.array(embeddings[file_names[i]]), np.array(embeddings[file_names[j]])
                cos_sim = np.dot(v_a, v_b) / (np.linalg.norm(v_a) * np.linalg.norm(v_b))
                if cos_sim > 0.75:
                    edges.append({"from": file_names[i], "to": file_names[j], "similarity": cos_sim})
        return jsonify({"nodes": nodes, "edges": edges})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# 5.1. 방문 기록 수집 API
@app.route('/api/history/collect', methods=['POST'])
def collect_history():
    """Chrome 확장 프로그램 등 클라이언트에서 전송한 방문 기록 데이터를 DB에 저장합니다."""

    # === 보안 TODO: 사용자 인증 구현 ===
    # 실제 서비스에서는 Authorization 헤더의 JWT 토큰 등을 검증하여
    # 해당 사용자의 이메일(user_email)을 안전하게 얻어야 합니다.
    # 예: user_email = verify_token_and_get_email(request.headers.get('Authorization'))
    # if not user_email: return jsonify({"error": "인증 실패"}), 401
    user_email = "test@example.com" # <<< 임시 값, 반드시 실제 인증 로직으로 교체 필요!

    data = request.json
    if not isinstance(data, list):
        log_api_interaction({ # 오류 로깅
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/history/collect", "user_email": user_email,
            "error": "Input data is not a list", "received_data_type": type(data).__name__
        })
        return jsonify({"error": "데이터는 리스트(배열) 형태여야 합니다."}), 400

    conn = get_db_connection()
    if conn is None:
        log_api_interaction({ # 오류 로깅
             "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/history/collect", "user_email": user_email,
            "error": "Failed to connect to the database"
        })
        return jsonify({"error": "데이터베이스 연결에 실패했습니다."}), 500

    cursor = conn.cursor()
    inserted_count = 0
    skipped_duplicate_count = 0
    skipped_invalid_count = 0
    error_count = 0

    for entry in data:
        if not isinstance(entry, dict):
            skipped_invalid_count += 1
            continue

        url = entry.get('url')
        timestamp = entry.get('timestamp') # ISO 8601 형식 기대 (예: "2023-10-27T10:00:00.000Z")
        title = entry.get('title') # 없을 수도 있음

        if not url or not timestamp: # 필수 값 확인
            skipped_invalid_count += 1
            continue

        try:
            # 데이터 삽입 시도
            cursor.execute(
                "INSERT INTO visit_history (url, title, timestamp, user_email) VALUES (?, ?, ?, ?)",
                (url, title, timestamp, user_email)
            )
            inserted_count += 1
        except sqlite3.IntegrityError: # UNIQUE 제약조건 위반 (이미 존재하는 데이터)
            skipped_duplicate_count += 1
        except Exception as e:
            error_count += 1
            print(f"DB Insert Error: {e}, Data: {entry}") # 서버 로그에 상세 오류 출력

    try:
        conn.commit() # 모든 삽입/건너뛰기 후 최종 커밋
    except Exception as e:
        conn.rollback()
        print(f"DB Commit Error: {e}")
        log_api_interaction({ # 커밋 오류 로깅
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/history/collect", "user_email": user_email,
            "error": f"Database commit failed: {e}", "received_count": len(data)
        })
        return jsonify({"error": f"데이터 저장 중 최종 커밋 실패: {e}"}), 500
    finally:
        conn.close()

    # 성공/부분 성공/실패에 대한 요약 로깅
    log_api_interaction({
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "api_endpoint": "/api/history/collect", "user_email": user_email,
        "received_count": len(data),
        "inserted_count": inserted_count,
        "skipped_duplicate_count": skipped_duplicate_count,
        "skipped_invalid_count": skipped_invalid_count,
        "error_count": error_count,
    })

    # 클라이언트에 결과 반환
    if error_count > 0:
        return jsonify({
            "message": f"일부 데이터 처리 실패. 성공: {inserted_count}, 중복: {skipped_duplicate_count}, 무효: {skipped_invalid_count}, 오류: {error_count}.",
            "status": "partial_error"
        }), 207 # Multi-Status
    else:
        return jsonify({
            "message": f"처리 완료. 성공: {inserted_count}, 중복: {skipped_duplicate_count}, 무효: {skipped_invalid_count}.",
            "status": "ok"
        }), 200 # OK

# 5.2. 방문 통계 API
@app.route('/api/history/stats', methods=['GET'])
def get_history_stats():
    """요청된 기간 동안의 방문 통계를 계산하여 반환합니다."""
    # === 보안 TODO: 사용자 인증 구현 ===
    user_email = "test@example.com" # <<< 임시 값

    # TODO: 기간 필터링 파라미터 처리 (예: ?period=week, ?start_date=..., ?end_date=...)
    # period = request.args.get('period', 'all')
    # start_date_str = request.args.get('start_date')
    # end_date_str = request.args.get('end_date')

    conn = get_db_connection()
    if conn is None: return jsonify({"error": "데이터베이스 연결 실패"}), 500

    try:
        # TODO: SQL 쿼리에 기간 필터링 로직 추가 (WHERE timestamp BETWEEN ? AND ?)
        query = "SELECT url, timestamp FROM visit_history WHERE user_email = ?"
        params = (user_email,)

        # Pandas DataFrame으로 데이터 로드
        df = pd.read_sql_query(query, conn, params=params)

        # 결과 로깅
        log_data = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/history/stats", "user_email": user_email,
            # "params": {"period": period, "start": start_date_str, "end": end_date_str},
        }

        if df.empty:
            log_data["message"] = "No data found for analysis"
            log_api_interaction(log_data)
            return jsonify({
                "total_visits": 0, "top_domains": {},
                "visits_by_hour": {h: 0 for h in range(24)},
                "visits_by_day": {day: 0 for day in ["월", "화", "수", "목", "금", "토", "일"]},
                "message": "분석할 방문 기록 데이터가 없습니다."
            }), 200

        # 데이터 전처리
        df['timestamp'] = pd.to_datetime(df['timestamp'], errors='coerce')
        df.dropna(subset=['timestamp'], inplace=True) # 유효하지 않은 타임스탬프 행 제거

        if df.empty: # 전처리 후 비었는지 다시 확인
            log_data["message"] = "No valid timestamp data after cleaning"
            log_api_interaction(log_data)
            return jsonify({"message": "유효한 방문 기록 데이터가 없습니다."}), 200

        # 도메인 추출 함수
        def extract_domain(url):
            try: return urlparse(url).netloc.lower() # 소문자로 통일
            except: return None
        df['domain'] = df['url'].apply(extract_domain)
        df.dropna(subset=['domain'], inplace=True) # 유효하지 않은 URL(도메인 추출 불가) 행 제거
        df = df[df['domain'] != ''] # 빈 도메인 제거

        # --- 통계 계산 ---
        # 1. 총 방문 수
        total_visits = len(df)

        # 2. 가장 많이 방문한 도메인 Top 10
        top_domains = df['domain'].value_counts().head(10).to_dict()

        # 3. 시간대별 방문 횟수 (0-23시)
        hourly_visits = df['timestamp'].dt.hour.value_counts().sort_index()
        hourly_stats = {hour: int(hourly_visits.get(hour, 0)) for hour in range(24)}

        # 4. 요일별 방문 횟수 (0:월요일 ~ 6:일요일)
        daily_visits = df['timestamp'].dt.weekday.value_counts().sort_index()
        day_names = ["월", "화", "수", "목", "금", "토", "일"]
        daily_stats = {day_names[day]: int(daily_visits.get(day, 0)) for day in range(7)}

        # 성공 로깅
        log_data["result_summary"] = {
             "total_visits": total_visits, "top_domain_count": len(top_domains),
             "hours_analyzed": len(hourly_stats), "days_analyzed": len(daily_stats)
        }
        log_api_interaction(log_data)

        # 결과 반환
        return jsonify({
            "total_visits": total_visits,
            "top_domains": top_domains,
            "visits_by_hour": hourly_stats,
            "visits_by_day": daily_stats,
        })

    except Exception as e:
        print(f"통계 API 처리 중 오류: {e}")
        traceback.print_exc()
        log_api_interaction({ # 오류 로깅
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/history/stats", "user_email": user_email,
            "error": str(e), "traceback": traceback.format_exc()
        })
        return jsonify({"error": f"통계 분석 중 오류 발생: {e}"}), 500
    finally:
        if conn: conn.close()

# 5.3. 방문 기록 검색 API
@app.route('/api/history/search', methods=['GET'])
def search_history():
    """쿼리 파라미터 'q'로 방문 기록의 제목 또는 URL을 검색합니다."""
    # === 보안 TODO: 사용자 인증 구현 ===
    user_email = "test@example.com" # <<< 임시 값

    query = request.args.get('q', '').strip() # 앞뒤 공백 제거
    if not query:
        return jsonify({"error": "검색어 파라미터 'q'가 필요합니다."}), 400

    try:
        # 페이지네이션 파라미터 (기본값 설정 및 타입 변환)
        page = int(request.args.get('page', '1'))
        limit = int(request.args.get('limit', '50')) # 기본 50개
        if page < 1: page = 1
        if limit < 1: limit = 50
        offset = (page - 1) * limit
    except ValueError:
        return jsonify({"error": "page 또는 limit 파라미터는 유효한 숫자여야 합니다."}), 400

    conn = get_db_connection()
    if conn is None: return jsonify({"error": "데이터베이스 연결 실패"}), 500

    results = []
    total_results = 0

    try:
        cursor = conn.cursor()
        search_term = f'%{query.lower()}%' # 소문자로 변환하여 검색

        # 검색 쿼리 실행 (최신순 정렬)
        cursor.execute(
            """
            SELECT url, title, timestamp
            FROM visit_history
            WHERE user_email = ? AND (LOWER(title) LIKE ? OR LOWER(url) LIKE ?)
            ORDER BY timestamp DESC
            LIMIT ? OFFSET ?
            """,
            (user_email, search_term, search_term, limit, offset)
        )
        # 결과를 딕셔너리 리스트로 변환
        results = [dict(row) for row in cursor.fetchall()]

        # 페이징을 위한 전체 결과 수 계산
        cursor.execute(
             """
            SELECT COUNT(*)
            FROM visit_history
            WHERE user_email = ? AND (LOWER(title) LIKE ? OR LOWER(url) LIKE ?)
            """,
            (user_email, search_term, search_term)
        )
        # fetchone() 결과는 튜플이므로 첫 번째 요소([0])를 가져옴
        total_results = cursor.fetchone()[0]

        # API 상호작용 로깅
        log_api_interaction({
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/history/search", "user_email": user_email,
            "query": query, "page": page, "limit": limit,
            "found_results_count": len(results),
            "total_results_count": total_results
        })

        # 결과 및 페이지 정보 반환
        return jsonify({
            "results": results,
            "page": page,
            "limit": limit,
            "total_results": total_results,
            "total_pages": (total_results + limit - 1) // limit if limit > 0 else 1
        })

    except Exception as e:
        print(f"검색 API 처리 중 오류: {e}")
        traceback.print_exc()
        log_api_interaction({ # 오류 로깅
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/history/search", "user_email": user_email,
            "query": query, "error": str(e), "traceback": traceback.format_exc()
        })
        return jsonify({"error": f"검색 중 오류 발생: {e}"}), 500
    finally:
        if conn: conn.close()
        
# --- ✨ 일반 로그인 API 엔드포인트 (예시) ---
@app.route('/api/login', methods=['POST'])
def handle_login():
    data = request.json
    email = data.get('email')
    password = data.get('password')

    print(f"[Backend] Received login request for: {email}") # 요청 수신 로그

    # === 보안 TODO: 실제 사용자 인증 로직 구현 ===
    # 1. DB에서 email로 사용자 조회
    # 2. 조회된 사용자의 해시된 비밀번호와 입력된 password 비교
    # 3. 인증 성공 시 JWT Access Token 및 Refresh Token 생성
    # === 임시 응답 (테스트용) ===
    if email and password: # 간단히 이메일/비번이 있으면 성공으로 간주
        print(f"[Backend] Login successful (dummy): {email}")
        dummy_access_token = f"dummy_access_{uuid.uuid4()}"
        dummy_refresh_token = f"dummy_refresh_{uuid.uuid4()}"
        log_api_interaction({ # 성공 로깅
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/login", "user_email": email, "status": "success (dummy)"
        })
        return jsonify({
            "message": "로그인 성공 (임시 응답)",
            "accessToken": dummy_access_token,
            "refreshToken": dummy_refresh_token
        }), 200
    else:
        print(f"[Backend] Login failed (dummy): Invalid input for {email}")
        log_api_interaction({ # 실패 로깅
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/login", "user_email": email, "status": "failed (dummy)",
            "reason": "Invalid email or password provided"
        })
        return jsonify({"message": "이메일 또는 비밀번호를 확인해주세요 (임시 응답)"}), 401 # Unauthorized

# --- ✨ Google 로그인 API 엔드포인트 (예시) ---
@app.route('/api/google-login', methods=['POST'])
def handle_google_login():
    data = request.json
    google_access_token = data.get('googleAccessToken')

    print(f"[Backend] Received Google login request (token starts with: {str(google_access_token)[:10]}...)") # 요청 수신 로그

    # === 보안 TODO: 실제 Google 토큰 검증 및 사용자 처리 로직 구현 ===
    # 1. 백엔드에서 Google API를 호출하여 googleAccessToken 검증 (유효성, 사용자 이메일 확인)
    # 2. 해당 이메일로 DB에서 사용자 조회 또는 신규 생성
    # 3. Memordo 시스템용 JWT Access Token 및 Refresh Token 생성
    # 4. 필요 시 Google Refresh Token 등 저장
    # === 임시 응답 (테스트용) ===
    if google_access_token: # 간단히 토큰이 있으면 성공으로 간주
        dummy_email = "google_user@example.com" # 임시 이메일
        print(f"[Backend] Google Login successful (dummy): {dummy_email}")
        dummy_access_token = f"dummy_access_{uuid.uuid4()}"
        dummy_refresh_token = f"dummy_refresh_{uuid.uuid4()}"
        log_api_interaction({ # 성공 로깅
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/google-login", "user_email": dummy_email, "status": "success (dummy)"
        })
        return jsonify({
            "message": "Google 로그인 성공 (임시 응답)",
            "accessToken": dummy_access_token,
            "refreshToken": dummy_refresh_token,
            "email": dummy_email, # 확장 프로그램에서 UI 업데이트를 위해 이메일 반환
            # 필요하다면 백엔드가 관리/갱신한 구글 토큰도 반환
            # "googleAccessToken": "...",
            # "googleRefreshToken": "..."
        }), 200
    else:
        print("[Backend] Google Login failed (dummy): No Google token provided")
        log_api_interaction({ # 실패 로깅
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/google-login", "status": "failed (dummy)",
            "reason": "No Google access token received"
        })
        return jsonify({"message": "Google 인증 토큰이 필요합니다 (임시 응답)"}), 400 # Bad Request
    
# # --- 6. Flask 앱 실행 ---
# #(py/run_server.py 를 사용하므로 이 부분은 주석 처리 또는 제거)
# if __name__ == '__main__':
#     print("Flask 서버를 시작합니다 (개발 모드)...")
#     # init_db() # 개발용 직접 실행 시 DB 초기화
#     app.run(host='0.0.0.0', port=5001, debug=True)