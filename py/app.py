# -*- coding: utf-8 -*-

from flask import Flask, request, jsonify
from flask_cors import CORS # CORS 추가
import numpy as np
import traceback
import datetime
import os
import json
from dotenv import load_dotenv # 1. python-dotenv import

# --- 1. 초기 설정: 환경 변수 및 경로 설정 ---

# .env 파일에서 환경 변수를 로드합니다.
load_dotenv() # 2. 이 함수를 호출해야 .env 파일의 내용이 환경 변수로 로드됩니다.

# 로그 파일을 저장할 디렉토리 경로를 설정합니다.
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "log")

# --- 2. AI 모듈 임포트 및 API 키 확인 ---

# Gemini API 키를 환경 변수에서 가져옵니다.
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    # 이 오류 메시지가 계속 보인다면, load_dotenv()가 제대로 작동하지 않거나 .env 파일 경로 문제일 수 있습니다.
    print("Flask App: CRITICAL - .env 파일에서 GEMINI_API_KEY를 로드하지 못했습니다. 환경 변수를 확인해주세요.")
    # 개발 중에는 여기서 프로그램을 중단시키는 것이 좋을 수 있습니다.
    # raise ValueError("GEMINI_API_KEY 환경 변수가 설정되지 않았습니다. .env 파일을 확인하거나 직접 설정해주세요.")
    # 실제 운영 시에는 강력한 오류 처리 또는 기본값 설정
else:
    print(f"Flask App: GEMINI_API_KEY 로드 성공 (첫 5자리: {GEMINI_API_KEY[:5]}...).")

# gemini_ai.py 파일에서 필요한 함수와 변수들을 가져옵니다.
# gemini_ai.py가 app.py와 같은 디렉토리에 있다고 가정합니다.
try:
    from gemini_ai import (
        get_embedding_for_text,
        query_gemini,
        execute_simple_task, # ✅ 수정: 올바른 함수 임포트
        DEFAULT_GEMINI_MODEL
    )
    # Gemini API 초기화는 gemini_ai.py 내부에서 처리됨 (genai.configure)
    print("Flask App: 'gemini_ai.py' 모듈 로드 성공.")
except ImportError as e:
    print(f"Flask App: CRITICAL - gemini_ai.py에서 모듈을 import 하는 데 실패했습니다: {e}")
    print("Flask App: gemini_ai.py 파일이 app.py와 동일한 디렉토리에 있는지, 필요한 모든 라이브러리가 설치되었는지 확인하세요.")
    exit(1) # Flask 앱 실행 중지

# --- 3. Flask 애플리케이션 설정 ---

app = Flask(__name__)
CORS(app) # 모든 라우트에 대해 CORS를 허용 (개발 중에는 편리, 프로덕션에서는 특정 도메인만 허용하도록 설정 권장)

# --- 4. 유틸리티 함수: 로깅 ---

def log_api_interaction(log_data):
    """API 상호작용을 JSONL 형식으로 로깅합니다."""
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        # 로그 파일명을 API 전용으로 변경하거나 기존 파일에 API 요청임을 명시
        api_log_filename = os.path.join(LOG_DIR, "api_interaction_log.jsonl")
        with open(api_log_filename, 'a', encoding='utf-8') as f:
            f.write(json.dumps(log_data, ensure_ascii=False) + '\n')
    except Exception as e:
        print(f"API 로깅 실패: {e}")

# --- 5. API 엔드포인트(라우트) 정의 ---

@app.route('/')
def home():
    """서버가 정상적으로 실행 중인지 확인하는 기본 엔드포인트입니다."""
    return jsonify({"message": "Gemini AI Python 백엔드 서버가 실행 중입니다.", "status": "ok"})

# --- 범용 작업 실행 엔드포인트 (요약, 메모, 키워드, 일반 채팅 등) ---
@app.route('/api/execute_task', methods=['POST'])
def api_execute_task():
    """
    Flutter 앱으로부터 텍스트 처리 작업을 요청받아 처리합니다.
    (요약, 메모, 키워드 추출, 일반 대화 등)
    """
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "요청 본문이 비어있습니다."}), 400

        task_type = data.get('task_type')
        user_input_ko = data.get('text')
        model_to_use = data.get('model', DEFAULT_GEMINI_MODEL) # 클라이언트에서 모델 지정 가능

        if not task_type or user_input_ko is None: # text가 빈 문자열일 수 있으므로 None 체크
            return jsonify({"error": "필수 파라미터 누락: task_type, text"}), 400

        print(f"[API /execute_task] 요청 수신: task_type='{task_type}', input='{user_input_ko[:50]}...'")

        result_text = "오류: 작업을 처리할 수 없습니다."
        log_data = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/execute_task",
            "task_type": task_type,
            "input_text": user_input_ko,
            "model_used": model_to_use,
        }

        # 작업 유형에 따라 적절한 함수를 호출합니다.
        if task_type == 'chat':
            # ✅ 수정: 'chat' 작업은 query_gemini 함수를 직접 호출합니다.
            result_text = query_gemini(user_input_ko, model_name=model_to_use)
        
        elif task_type in ['summarize', 'memo', 'keyword']:
            # ✅ 수정: 요약, 메모, 키워드 추출 작업은 execute_simple_task 함수로 통합하여 처리합니다.
            # 이전 execute_adaptive_gemini_task 함수는 정의되어 있지 않아 오류가 발생했습니다.
            result_text = execute_simple_task(task_type, user_input_ko)
        
        else:
            # 지원하지 않는 작업 유형일 경우 에러를 반환합니다.
            log_data["error"] = f"지원하지 않는 task_type: {task_type}"
            log_api_interaction(log_data)
            return jsonify({"error": f"지원하지 않는 task_type: {task_type}"}), 400

        # 처리 결과를 로그에 기록합니다.
        log_data["output_text"] = result_text
        log_api_interaction(log_data)

        # AI 모델이 에러를 반환한 경우, 서버 에러로 처리합니다.
        if result_text is not None and "Error:" in result_text : # execute_simple_task 등에서 "Error:" 접두사 사용
             return jsonify({"error": result_text}), 500 # 서버 내부 오류로 간주할 수 있음

        # 최종 결과를 JSON 형태로 반환합니다.
        return jsonify({"result": result_text})

    except Exception as e:
        # API 처리 중 예외 발생 시, 상세 내용을 서버 로그에 기록하고 클라이언트에는 일반적인 오류 메시지를 보냅니다.
        print(f"API /execute_task 처리 중 예외: {e}")
        traceback.print_exc()
        log_api_interaction({
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/execute_task",
            "error": str(e),
            "traceback": traceback.format_exc()
        })
        return jsonify({"error": "서버 내부 오류 발생"}), 500

@app.route('/api/generate-graph-data', methods=['POST'])
def generate_graph_data():
    """
    플러터로부터 노트 파일들의 내용을 리스트로 받아,
    Gemini AI를 이용해 임베딩을 수행하고 노드와 엣지 정보를 계산하여 반환합니다.
    (상세 로깅 기능 추가됨)
    """
    try:
        # 1. 플러터에서 보낸 JSON 데이터(노트 목록)를 수신합니다.
        notes_data = request.get_json()
        if not notes_data or not isinstance(notes_data, list):
            return jsonify({"error": "잘못되거나 없는 데이터입니다."}), 400

        print(f"[그래프 생성] {len(notes_data)}개의 노트에 대한 임베딩을 시작합니다.")

        # 2. 모든 노트를 임베딩하고, 결과를 딕셔너리에 저장합니다.
        embeddings = {}
        for note in notes_data:
            file_name = note.get('fileName')
            content = note.get('content')
            if file_name and content:
                # gemini_ai.py의 함수를 사용하여 텍스트를 임베딩합니다.
                vector = get_embedding_for_text(content)
                if vector:
                    embeddings[file_name] = vector
        
        print(f"[그래프 생성] {len(embeddings.keys())}개 노트 임베딩 완료.")

        if not embeddings:
            return jsonify({"nodes": [], "edges": []})

        # 3. 모든 임베딩 벡터 쌍에 대해 코사인 유사도를 계산하여 엣지를 생성합니다.
        print("\n--- [그래프 생성] 엣지(연결선) 생성 시작 ---")
        nodes = [{"id": file_name} for file_name in embeddings.keys()]
        edges = []
        file_names = list(embeddings.keys())
        similarity_threshold = 0.75 
        print(f"유사도 임계값(Threshold): {similarity_threshold}")
        
        # 모든 파일 쌍에 대해 반복
        for i in range(len(file_names)):
            for j in range(i + 1, len(file_names)):
                file_a = file_names[i]
                file_b = file_names[j]

                vector_a = np.array(embeddings[file_a])
                vector_b = np.array(embeddings[file_b])

                # 코사인 유사도 계산
                cos_sim = np.dot(vector_a, vector_b) / (np.linalg.norm(vector_a) * np.linalg.norm(vector_b))

                # [로그 추가] 모든 비교 쌍의 유사도 점수를 로그로 출력합니다.
                print(f"  - 비교: '{os.path.basename(file_a)}' <-> '{os.path.basename(file_b)}' | 유사도: {cos_sim:.4f}")

                # 유사도가 설정한 임계값 이상일 때만 '연결된 관계'로 판단합니다.
                if cos_sim > similarity_threshold:
                    # [로그 추가] 임계값을 넘는 경우, 엣지를 추가하고 로그를 남깁니다.
                    print(f"    ✅ 엣지 생성! ({cos_sim:.4f} > {similarity_threshold})")
                    edges.append({
                        "from": file_a,
                        "to": file_b,
                        "similarity": cos_sim
                    })
        
        print(f"\n[그래프 생성] 총 {len(edges)}개의 연결 관계(엣지)를 찾았습니다.")
        
        # 4. 최종 그래프 데이터를 JSON 형태로 플러터에 반환합니다.
        return jsonify({"nodes": nodes, "edges": edges})

    except Exception as e:
        print(f"Error in /api/generate-graph-data: {e}")
        traceback.print_exc() # 상세한 에러 로그를 보기 위해 추가
        return jsonify({"error": str(e)}), 500

# --- (주석 처리) 비활성화된 RAG 및 기타 엔드포인트 ---
# 아래 API들은 현재의 gemini_ai.py 모듈과 호환되지 않아 주석 처리되었습니다.
# RAG(검색 증강 생성) 기능을 다시 구현하려면 Gemini 임베딩 모델에 맞춰 재설계가 필요합니다.
"""
# --- RAG 기반 작업 엔드포인트 ---
@app.route('/api/rag_query', methods=['POST'])
def api_rag_query():
    # 이 기능은 재설계가 필요합니다.
    return jsonify({"error": "RAG 기능은 현재 비활성화되어 있습니다."}), 501

# --- 문서 인덱싱 트리거 엔드포인트 ---
@app.route('/api/index_documents', methods=['POST']) # GET도 가능하지만, 상태 변경을 유발하므로 POST 권장
def api_index_documents():
    # 이 기능은 재설계가 필요합니다.
    return jsonify({"error": "문서 인덱싱 기능은 현재 비활성화되어 있습니다."}), 501

# --- (선택적) 키워드 비교 엔드포인트 ---
@app.route('/api/compare_keywords_direct', methods=['POST'])
def api_compare_keywords_direct():
    # 이 기능은 재설계가 필요합니다.
    return jsonify({"error": "키워드 비교 기능은 현재 비활성화되어 있습니다."}), 501
"""

# --- 6. Flask 앱 실행 ---

if __name__ == '__main__':
    # 이 스크립트가 직접 실행될 때만 Flask 서버를 시작합니다.
    # gemini_ai.py 파일에서 if __name__ == "__main__": 부분은 실행되지 않도록 주의
    # (app.py를 직접 실행하므로, gemini_ai.py는 모듈로만 사용됨)
    # host='0.0.0.0'은 모든 네트워크 인터페이스에서 접속 허용 (개발 시 편리, 실제 배포 시 보안 고려)
    # debug=True는 개발 중에만 사용, 코드 변경 시 자동 재시작 및 디버깅 정보 제공
    print("Flask 서버를 시작합니다...")
    app.run(host='0.0.0.0', port=5001, debug=True)
