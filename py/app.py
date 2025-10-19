# py/app.py

from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
import traceback
import datetime
import os
import json
import asyncio

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

# --- 6. Flask 앱 실행 (변경 없음) ---
if __name__ == '__main__':
    print("Flask 서버를 시작합니다...")
    app.run(host='0.0.0.0', port=5001, debug=True)