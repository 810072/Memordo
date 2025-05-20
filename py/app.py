from flask import Flask, request, jsonify
from flask_cors import CORS # CORS 추가
import traceback
import datetime
import os
from dotenv import load_dotenv # 1. python-dotenv import

# --- .env 파일에서 환경 변수 로드 ---
load_dotenv() # 2. 이 함수를 호출해야 .env 파일의 내용이 환경 변수로 로드됩니다.

# --- GEMINI_API_KEY 로드 및 확인 ---
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    # 이 오류 메시지가 계속 보인다면, load_dotenv()가 제대로 작동하지 않거나 .env 파일 경로 문제일 수 있습니다.
    print("Flask App: CRITICAL - .env 파일에서 GEMINI_API_KEY를 로드하지 못했습니다. 환경 변수를 확인해주세요.")
    # 개발 중에는 여기서 프로그램을 중단시키는 것이 좋을 수 있습니다.
    # raise ValueError("GEMINI_API_KEY 환경 변수가 설정되지 않았습니다. .env 파일을 확인하거나 직접 설정해주세요.")
    # 실제 운영 시에는 강력한 오류 처리 또는 기본값 설정
else:
    print(f"Flask App: GEMINI_API_KEY 로드 성공 (첫 5자리: {GEMINI_API_KEY[:5]}...).")
# gemini_ai.py에서 필요한 함수 및 변수들을 import 합니다.
# gemini_ai.py가 app.py와 같은 디렉토리에 있다고 가정합니다.
try:
    from gemini_ai import (
        get_sbert_model,
        initialize_chromadb,
        query_gemini, # 직접 Gemini 호출이 필요한 경우
        execute_gemini_task, # 단순 작업 실행
        execute_adaptive_gemini_task, # 적응형 작업 실행
        find_related_documents_by_vector_similarity, # RAG 문서 검색
        index_documents, # 문서 인덱싱 (백그라운드 실행 고려 필요)
        perform_comparison_task, # 키워드 비교 (API 설계 재고 필요)
        task_prompts, # 키워드 추출 등 프롬프트 사용 시
        DEFAULT_GEMINI_MODEL,
        SBERT_MODEL_NAME,
        DOC_DIR, # index_documents에서 사용
        # gemini_ai.py 내의 로깅 함수를 사용하거나 여기서 새로 정의
        LOG_DIR, LOG_FILENAME # 로깅 경로
    )
    # Gemini API 초기화는 gemini_ai.py 내부에서 처리됨 (genai.configure)
    # 또는 여기서 명시적으로 os.getenv("GEMINI_API_KEY") 확인 후 configure
    if not os.getenv("GEMINI_API_KEY"):
        print("Flask App: CRITICAL - GEMINI_API_KEY 환경 변수가 설정되지 않았습니다.")
        # exit(1) # 실제 운영 시에는 강력한 오류 처리 또는 기본값 설정
except ImportError as e:
    print(f"Flask App: CRITICAL - gemini_ai.py에서 모듈을 import 하는 데 실패했습니다: {e}")
    print("Flask App: gemini_ai.py 파일이 app.py와 동일한 디렉토리에 있는지, 필요한 모든 라이브러리가 설치되었는지 확인하세요.")
    exit(1) # Flask 앱 실행 중지

app = Flask(__name__)
CORS(app) # 모든 라우트에 대해 CORS를 허용 (개발 중에는 편리, 프로덕션에서는 특정 도메인만 허용하도록 설정 권장)

# --- 애플리케이션 시작 시 모델 및 DB 초기화 (한 번만 실행) ---
try:
    print("Flask App: SBERT 모델 초기화 중...")
    sbert_model = get_sbert_model() # 전역 변수 SBERT_MODEL에 할당됨
    print("Flask App: ChromaDB 초기화 중...")
    chroma_collection = initialize_chromadb() # 전역 변수 CHROMA_COLLECTION에 할당됨
    print("Flask App: 모델 및 DB 성공적으로 초기화 완료.")
except SystemExit as e: # gemini_ai.py 내부의 SystemExit 처리
    print(f"Flask App: CRITICAL - 초기화 중 시스템 종료 요청: {e}")
    exit(1)
except Exception as e:
    print(f"Flask App: CRITICAL - 모델 또는 DB 초기화 중 예외 발생: {e}")
    traceback.print_exc()
    exit(1) # 초기화 실패 시 앱 실행 중지

# --- 로깅 함수 (gemini_ai.py의 로깅을 재사용하거나 여기서 간단히 구현) ---
def log_api_interaction(log_data):
    """API 상호작용을 JSONL 형식으로 로깅합니다."""
    try:
        os.makedirs(LOG_DIR, exist_ok=True) # gemini_ai.py의 LOG_DIR 사용
        # 로그 파일명을 API 전용으로 변경하거나 기존 파일에 API 요청임을 명시
        api_log_filename = os.path.join(LOG_DIR, "api_interaction_log.jsonl")
        with open(api_log_filename, 'a', encoding='utf-8') as f:
            f.write(json.dumps(log_data, ensure_ascii=False) + '\n')
    except Exception as e:
        print(f"API 로깅 실패: {e}")

# --- 기본 라우트 ---
@app.route('/')
def home():
    return jsonify({"message": "Gemini AI Python 백엔드 서버가 실행 중입니다.", "status": "ok"})

# --- 범용 작업 실행 엔드포인트 (요약, 메모, 키워드, 일반 채팅 등) ---
@app.route('/api/execute_task', methods=['POST'])
def api_execute_task():
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

        if task_type == 'chat':
            result_text = execute_gemini_task(user_input_ko, model=model_to_use)
        elif task_type in ['summarize', 'memo']:
            # execute_adaptive_gemini_task는 내부적으로 분류 -> 프롬프트 생성 -> 실행
            result_text = execute_adaptive_gemini_task(user_input_ko, task_type, model=model_to_use)
        elif task_type == 'keyword':
            # gemini_ai.py의 main 함수 내 키워드 처리 로직 참고
            # 키워드 프롬프트는 영어 기반, [TEXT]만 한국어 -> Gemini가 처리
            # 또는 task_prompts 자체를 한국어로 번역하여 사용 (gemini_ai.py에서 이미 일부 수정됨)
            keyword_prompt_template = task_prompts.get(task_type)
            if not keyword_prompt_template:
                return jsonify({"error": f"지원하지 않는 task_type 또는 keyword 프롬프트 없음: {task_type}"}), 400
            
            final_prompt = keyword_prompt_template.replace("[TEXT]", user_input_ko)
            result_text = query_gemini(final_prompt, model_name=model_to_use) # query_gemini가 토큰 사용량 출력
        else:
            log_data["error"] = f"지원하지 않는 task_type: {task_type}"
            log_api_interaction(log_data)
            return jsonify({"error": f"지원하지 않는 task_type: {task_type}"}), 400

        log_data["output_text"] = result_text
        log_api_interaction(log_data) # API 로깅

        if result_text is not None and "Error:" in result_text : # execute_gemini_task 등에서 "Error:" 접두사 사용
             return jsonify({"error": result_text}), 500 # 서버 내부 오류로 간주할 수 있음

        return jsonify({"result": result_text})

    except Exception as e:
        print(f"API /execute_task 처리 중 예외: {e}")
        traceback.print_exc()
        log_api_interaction({
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/execute_task",
            "error": str(e),
            "traceback": traceback.format_exc()
        })
        return jsonify({"error": "서버 내부 오류 발생"}), 500


# --- RAG 기반 작업 엔드포인트 ---
@app.route('/api/rag_query', methods=['POST'])
def api_rag_query():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "요청 본문이 비어있습니다."}), 400

        user_query_ko = data.get('query')
        model_to_use = data.get('model', DEFAULT_GEMINI_MODEL)

        if not user_query_ko:
            return jsonify({"error": "필수 파라미터 누락: query"}), 400

        print(f"[API /rag_query] 요청 수신: query='{user_query_ko[:50]}...'")
        log_data = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/rag_query",
            "query": user_query_ko,
            "model_used": model_to_use,
            "sbert_model_for_rag": SBERT_MODEL_NAME
        }

        # 1. 관련 문서 검색 (gemini_ai.py의 로직 사용)
        related_contexts_info = find_related_documents_by_vector_similarity(user_query_ko, top_n=3)
        log_data["retrieved_contexts_count"] = len(related_contexts_info)
        log_data["retrieved_contexts_preview"] = [
            {"filename": ctx.get("filename"), "score": ctx.get("score")} for ctx in related_contexts_info
        ]


        if not related_contexts_info:
            # 관련 문서가 없을 경우, 일반 chat처럼 직접 Gemini에게 질문 (Fallback)
            # 또는 특정 메시지 반환
            print(f"[API /rag_query] 관련 문서를 찾지 못해 Fallback 실행.")
            result_text = execute_gemini_task(
                f"다음 질문에 대해 당신이 아는 선에서 답변해주세요: \"{user_query_ko}\"", # Fallback 프롬프트 예시
                model=model_to_use
            )
            log_data["rag_fallback_invoked"] = True
        else:
            # 2. 검색된 컨텍스트를 활용하여 최종 프롬프트 구성 (gemini_ai.py 로직 참고)
            augmented_context_ko_str = ""
            for i, ctx_info in enumerate(related_contexts_info):
                augmented_context_ko_str += f"\n--- 관련 한국어 컨텍스트 {i+1} (출처: {ctx_info['filename']}) ---\n"
                augmented_context_ko_str += ctx_info['context_text_ko'] + "\n"

            final_rag_prompt_ko = f"""다음 질문에 답해주세요: "{user_query_ko}"

아래 제공된 한국어 컨텍스트 정보를 사용하세요:
{augmented_context_ko_str}

위 컨텍스트를 바탕으로 질문에 대한 답변을 한국어로 생성해주세요. 만약 컨텍스트에 답이 없다면, 없다고 명시해주세요.
"""
            # print(f"  RAG 프롬프트 (일부): {final_rag_prompt_ko[:300]}...") # 디버깅용
            result_text = execute_gemini_task(final_rag_prompt_ko, model=model_to_use)

        log_data["output_text"] = result_text
        log_api_interaction(log_data)

        if "Error:" in result_text:
            return jsonify({"error": result_text, "retrieved_contexts": related_contexts_info}), 500
            
        return jsonify({"result": result_text, "retrieved_contexts": related_contexts_info})

    except Exception as e:
        print(f"API /rag_query 처리 중 예외: {e}")
        traceback.print_exc()
        log_api_interaction({
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/rag_query",
            "error": str(e),
            "traceback": traceback.format_exc()
        })
        return jsonify({"error": "서버 내부 오류 발생"}), 500

# --- 문서 인덱싱 트리거 엔드포인트 ---
@app.route('/api/index_documents', methods=['POST']) # GET도 가능하지만, 상태 변경을 유발하므로 POST 권장
def api_index_documents():
    print(f"[API /index_documents] 요청 수신")
    log_data = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "api_endpoint": "/api/index_documents",
        "doc_dir_to_index": DOC_DIR # gemini_ai.py의 DOC_DIR
    }
    try:
        # index_documents 함수는 내부적으로 print 문을 많이 사용하므로,
        # 실제 운영 시에는 로깅 라이브러리(logging)를 사용하도록 수정하는 것이 좋음.
        # 이 작업은 오래 걸릴 수 있으므로, 비동기 처리(Celery 등)를 고려하거나,
        # 클라이언트에게 작업이 시작되었음을 알리고 완료까지 기다리지 않게 할 수 있음 (HTTP 202 Accepted).
        # 여기서는 간단하게 동기적으로 실행.
        # index_documents() 함수가 반환값이 특별히 없다면 성공 메시지만 전달.
        # 만약 상세 결과를 반환한다면 그것을 사용.
        # 여기서는 gemini_ai.py의 index_documents는 print로 결과를 출력하므로,
        # API 응답으로는 간단한 메시지만 보냅니다.
        
        # 이 함수를 직접 호출하면 Flask 요청 핸들러가 길게 블로킹될 수 있습니다.
        # 경고: 실제 운영 환경에서는 백그라운드 작업으로 전환하는 것을 강력히 권장합니다.
        print(f"[API /index_documents] 문서 인덱싱 시작 (DOC_DIR: {DOC_DIR})...")
        index_documents(DOC_DIR) # gemini_ai.py의 함수 호출
        message = "문서 인덱싱 작업이 요청되었고, 서버 로그를 확인하여 진행 상황을 파악하세요."
        
        log_data["status"] = "success" # 실제로는 index_documents의 상세 결과에 따라 달라짐
        log_data["message"] = message
        log_api_interaction(log_data)
        print(f"[API /index_documents] 문서 인덱싱 완료 추정.")
        return jsonify({"message": message, "status": "อาจจะ initiated"}), 202 # 202 Accepted
    except Exception as e:
        print(f"API /index_documents 처리 중 예외: {e}")
        traceback.print_exc()
        log_data["status"] = "error"
        log_data["error"] = str(e)
        log_api_interaction(log_data)
        return jsonify({"error": f"문서 인덱싱 중 오류 발생: {str(e)}"}), 500

# --- (선택적) 키워드 비교 엔드포인트 ---
# perform_comparison_task는 로그 파일을 읽고 사용자 인터랙션이 필요한 부분이 있어 API화가 복잡.
# API로 만들려면, 예를 들어 두 개의 키워드 세트를 직접 받거나,
# 로그 파일 목록을 제공하고 사용자가 ID를 선택하여 요청하는 방식으로 변경 필요.
# 가장 간단한 방법은 클라이언트(Dart)가 두 키워드 텍스트를 직접 전달하는 것.
@app.route('/api/compare_keywords_direct', methods=['POST'])
def api_compare_keywords_direct():
    try:
        data = request.get_json()
        keywords1_ko = data.get('keywords1_text') # "키워드1: 점수\n키워드2: 점수" 형태의 텍스트
        keywords2_ko = data.get('keywords2_text')
        model_to_use = data.get('model', DEFAULT_GEMINI_MODEL)

        if not keywords1_ko or not keywords2_ko:
            return jsonify({"error": "필수 파라미터 누락: keywords1_text, keywords2_text"}), 400
        
        print(f"[API /compare_keywords_direct] 요청 수신")
        log_data = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "api_endpoint": "/api/compare_keywords_direct",
            "input_keywords1": keywords1_ko,
            "input_keywords2": keywords2_ko,
            "model_used": model_to_use
        }

        # gemini_ai.py의 perform_comparison_task 내부 로직 중 Gemini 호출 부분만 활용
        comparison_prompt_ko = task_prompts["comparison"]
        comparison_prompt_ko = comparison_prompt_ko.replace("[KEYWORDS1]", keywords1_ko)
        comparison_prompt_ko = comparison_prompt_ko.replace("[KEYWORDS2]", keywords2_ko)
        
        comparison_result_text = query_gemini(comparison_prompt_ko, model_name=model_to_use)

        if "Error:" in comparison_result_text:
            log_data["error"] = comparison_result_text
            log_api_interaction(log_data)
            return jsonify({"error": f"유사성 평가 중 오류: {comparison_result_text}"}), 500

        # 점수 추출 (gemini_ai.py의 로직 활용)
        score_text_match = re.search(r"(\d*\.\d+|\d+)", comparison_result_text.strip())
        if score_text_match:
            score = float(score_text_match.group(1))
            result_message = f"키워드 기반 유사성 점수: {score:.2f}"
            log_data["score"] = score
            log_data["output_text"] = result_message
            log_api_interaction(log_data)
            return jsonify({"result": result_message, "score": score, "raw_gemini_output": comparison_result_text})
        else:
            result_message = f"유사성 평가 결과 (점수 추출 불가): '{comparison_result_text}'"
            log_data["output_text"] = result_message
            log_data["error"] = "Score extraction failed"
            log_api_interaction(log_data)
            return jsonify({"error": result_message, "raw_gemini_output": comparison_result_text}), 500

    except Exception as e:
        print(f"API /compare_keywords_direct 처리 중 예외: {e}")
        traceback.print_exc()
        # ... 로깅 ...
        return jsonify({"error": "서버 내부 오류 발생"}), 500


# --- Flask 앱 실행 ---
if __name__ == '__main__':
    # gemini_ai.py 파일에서 if __name__ == "__main__": 부분은 실행되지 않도록 주의
    # (app.py를 직접 실행하므로, gemini_ai.py는 모듈로만 사용됨)
    # host='0.0.0.0'은 모든 네트워크 인터페이스에서 접속 허용 (개발 시 편리, 실제 배포 시 보안 고려)
    # debug=True는 개발 중에만 사용, 코드 변경 시 자동 재시작 및 디버깅 정보 제공
    print("Flask 서버를 시작합니다...")
    app.run(host='0.0.0.0', port=5001, debug=True)