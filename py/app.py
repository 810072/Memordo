# py/app.py

from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
import traceback
import datetime
import os
import json
from dotenv import load_dotenv
import asyncio # [수정] asyncio 라이브러리를 임포트합니다.

# --- 1. 초기 설정 ---
load_dotenv()
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "log")

# --- 2. AI 모듈 및 워크플로우 임포트 ---
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    print("CRITICAL - .env 파일에서 GEMINI_API_KEY를 로드하지 못했습니다.")
else:
    print(f"GEMINI_API_KEY 로드 성공 (첫 5자리: {GEMINI_API_KEY[:5]}...).")

try:
    from gemini_ai import get_embedding_for_text, get_embeddings_batch, query_gemini, execute_simple_task, DEFAULT_GEMINI_MODEL
    print("'gemini_ai.py' 모듈 로드 성공.")
    
    from rag_workflow import build_rag_workflow
    print("'rag_workflow.py' 모듈 로드 성공.")
    
except ImportError as e:
    print(f"CRITICAL - 모듈 import 실패: {e}")
    exit(1)

# --- 3. Flask 앱 설정 ---
app = Flask(__name__)
CORS(app)

# --- 4. 유틸리티 함수: 로깅 ---
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

@app.route('/api/rag_chat', methods=['POST'])
def rag_chat():
    """
    RAG 워크플로우를 실행하여 사용자의 질문에 답변합니다.
    """
    data = request.json
    if not data or 'query' not in data or 'notes' not in data or 'edges' not in data:
        return jsonify({'error': '잘못된 요청. query, notes, edges가 필요합니다.'}), 400

    # [수정] 현재 스레드를 위한 asyncio 이벤트 루프를 설정합니다.
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    
    result = {} # 결과를 저장할 변수

    try:
        rag_app = build_rag_workflow()
        inputs = {
            "question": data['query'],
            "notes": data['notes'],
            "edges": data['edges'],
        }
        # invoke는 동기 함수이지만, 내부적으로 비동기 코드를 실행하므로
        # 이벤트 루프가 설정된 컨텍스트 내에서 호출해야 합니다.
        result = rag_app.invoke(inputs)
        
        log_api_interaction({
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/rag_chat",
            "input_query": data['query'],
            "output_answer": result.get('answer', 'N/A'),
            "final_context": result.get('final_context', 'N/A')
        })
        
        return jsonify({'result': result.get('answer')})
        
    except Exception as e:
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
        # [수정] 작업이 끝나면 이벤트 루프를 닫아줍니다.
        loop.close()

# ... (나머지 /api/execute_task, /api/get-embeddings 등 엔드포인트는 동일) ...
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
        if not task_type or user_input_ko is None:
            return jsonify({"error": "필수 파라미터 누락"}), 400
        if task_type == 'chat':
            result_text = query_gemini(user_input_ko)
        elif task_type in ['summarize', 'memo', 'keyword']:
            result_text = execute_simple_task(task_type, user_input_ko)
        else:
            return jsonify({"error": f"지원하지 않는 task_type: {task_type}"}), 400
        return jsonify({"result": result_text})
    except Exception as e:
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

# --- 6. Flask 앱 실행 ---
if __name__ == '__main__':
    print("Flask 서버를 시작합니다...")
    app.run(host='0.0.0.0', port=5001, debug=True)