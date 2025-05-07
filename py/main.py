# main.py
import datetime
import json
import os
import traceback

# 설정 및 상수 로드
from config import (
    DEFAULT_OLLAMA_MODEL, DOC_DIR, LOG_DIR, LOG_FILENAME, SBERT_MODEL_NAME,
    CHROMA_DB_PATH, BASE_DIR # BASE_DIR 추가
)

# 유틸리티 및 작업 모듈 초기화/로드
from utils.embedder import get_sbert_model
from utils.vector_db import initialize_chromadb
from core.tasks import (
    perform_adaptive_task,
    perform_keyword_extraction,
    perform_comparison,
    perform_indexing,
    perform_rag_query,
    perform_chat_task # 추가
)

def ensure_directories():
    """필수 디렉토리가 존재하는지 확인하고 없으면 생성합니다."""
    try:
        os.makedirs(DOC_DIR, exist_ok=True)
        os.makedirs(LOG_DIR, exist_ok=True)
        os.makedirs(CHROMA_DB_PATH, exist_ok=True)
        print(f"문서 디렉토리 확인: {DOC_DIR}")
        print(f"로그 파일 위치 확인: {LOG_FILENAME}")
        print(f"ChromaDB 저장 경로 확인: {CHROMA_DB_PATH}")
    except OSError as e:
        print(f"[치명적 오류] 필수 디렉토리 생성 불가: {e}. 스크립트를 종료합니다.")
        raise SystemExit(f"디렉토리 생성 실패: {e}")

def main_app_loop():
    """메인 애플리케이션 루프를 실행합니다."""
    try:
        # 애플리케이션 시작 시 모델 및 DB 초기화
        get_sbert_model()
        initialize_chromadb()
    except SystemExit as e:
        print(f"초기화 실패로 프로그램을 종료합니다: {e}")
        return # 초기화 실패 시 루프 진입 안 함
    except Exception as e: # 기타 초기화 예외
        print(f"초기화 중 예기치 않은 오류: {e}")
        traceback.print_exc()
        return

    model_to_use_llm = DEFAULT_OLLAMA_MODEL

    task_mapping = {
        '1': 'summarize', 
        '2': 'memo', 
        '3': 'keyword', 
        '4': 'chat',
        '5': 'comparison',
        '6': 'index_vector_db', # 작업명 변경됨 (tasks.py와 일치)
        '7': 'related_task_vector_rag',
    }

    while True:
        print("\n" + "="*10 + " 작업 선택 " + "="*10)
        print("1. 요약 (Summarize) [단일 텍스트, 최적화]")
        print("2. 메모 (Memo) [단일 텍스트, 최적화]")
        print("3. 키워드 추출 (Keyword) [단일 텍스트 대상, 결과 로깅]")
        print("4. 일반 대화 (Chat)")
        print("5. 키워드 로그 비교 (Comparison) [3번 작업 결과 활용]")
        print("--- 문서 관리 & RAG ---")
        print(f"6. 문서 벡터 인덱싱 (index) ['{DOC_DIR}' 내 .md]")
        print(f"7. 주제 관련 작업 (RAG) [벡터 DB 검색 기반]")
        print("exit: 종료")
        print("="*32)

        choice = input("선택: ").lower().strip()
        if choice == 'exit':
            break

        current_task_name = "unknown_task"
        final_result_for_display = "오류: 처리되지 않음"
        log_this_run = True
        user_input_to_log = ""
        additional_log_data = {}

        try:
            if choice == '1' or choice == '2': # 요약, 메모 (Adaptive)
                current_task_name = task_mapping[choice]
                user_input_to_log = input("작업할 텍스트를 입력하세요 (한국어): ")
                if not user_input_to_log.strip():
                    print("[알림] 입력이 비어있습니다."); log_this_run = False; continue
                final_result_for_display = perform_adaptive_task(user_input_to_log, current_task_name, model=model_to_use_llm)
            
            elif choice == '3': # 키워드 추출
                current_task_name = task_mapping[choice]
                user_input_to_log = input("키워드를 추출할 텍스트를 입력하세요 (한국어): ")
                if not user_input_to_log.strip():
                    print("[알림] 입력이 비어있습니다."); log_this_run = False; continue
                # perform_keyword_extraction은 (표시용 결과, 원본 영어 키워드) 반환
                final_result_for_display, original_en_keywords = perform_keyword_extraction(user_input_to_log, model=model_to_use_llm)
                if original_en_keywords: # 로그에 원본 영어 키워드도 저장
                    additional_log_data['original_english_keywords'] = original_en_keywords
            
            elif choice == '4': # 일반 대화
                current_task_name = task_mapping[choice]
                user_input_to_log = input("질문을 입력하세요 (한국어): ")
                if not user_input_to_log.strip():
                    print("[알림] 입력이 비어있습니다."); log_this_run = False; continue
                final_result_for_display = perform_chat_task(user_input_to_log, model=model_to_use_llm)

            elif choice == '5': # 키워드 로그 비교
                current_task_name = task_mapping[choice]
                # user_input_to_log은 이 작업에서 사용자가 직접 입력하는 것이 아님.
                final_result_for_display = perform_comparison(model=model_to_use_llm)
                # perform_comparison은 자체적으로 결과를 print하므로, 여기서는 final_result_for_display에 할당만.
                # 로깅은 이 작업의 특성상 선택적. 여기서는 로깅 안 함.
                log_this_run = False 
                print("\n" + "="*30); print(f"결과 ({current_task_name}):"); print(final_result_for_display); print("="*30 + "\n")


            elif choice == '6': # 문서 벡터 인덱싱
                current_task_name = task_mapping[choice] # index_vector_db
                perform_indexing(DOC_DIR) # DOC_DIR은 config에서 가져옴
                log_this_run = False # 인덱싱 자체는 상세 로그를 남기지 않음 (내부에서 메시지 출력)
            
            elif choice == '7': # RAG 작업
                current_task_name = task_mapping[choice] # related_task_vector_rag
                user_input_to_log = input("질문 또는 정리할 주제를 입력하세요 (한국어): ")
                if not user_input_to_log.strip():
                    print("[알림] 입력이 비어있습니다."); log_this_run = False; continue
                
                # perform_rag_query는 (결과, 추가 로그 정보) 반환
                final_result_for_display, rag_log_meta = perform_rag_query(user_input_to_log, model=model_to_use_llm)
                additional_log_data.update(rag_log_meta)
                # RAG 실패 시 Fallback 로직은 perform_rag_query 내에서 처리하고,
                # 그 결과(일반 chat 결과)가 final_result_for_display에 담김.
                # 작업명은 fallback 시 perform_rag_query 내부에서 수정될 수 있음 (예: chat_fallback_after_rag_fail)
                # 이 경우 current_task_name을 업데이트 해주는 것이 좋음. (현재는 안함)

            else:
                print("[오류] 잘못된 선택입니다. 메뉴에 있는 번호나 'exit'를 입력해주세요.")
                log_this_run = False
                current_task_name = "invalid_choice"

            # --- 결과 출력 (필요한 경우) ---
            if current_task_name not in ["unknown_task", "invalid_choice", "index_vector_db"] and choice != '5':
                # comparison(5)은 자체적으로 결과를 출력함.
                print("\n" + "="*30)
                print(f"결과 ({current_task_name}):")
                print(final_result_for_display)
                print("="*30 + "\n")

            # --- 로깅 ---
            if log_this_run and current_task_name not in ["unknown_task", "invalid_choice"]:
                log_entry = {
                    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    "task": current_task_name,
                    "input": user_input_to_log,
                    "output": final_result_for_display, # LLM의 최종 응답 (한국어)
                    "llm_model_used": model_to_use_llm,
                }
                if 'sbert_model_for_rag' in additional_log_data or SBERT_MODEL_NAME: # RAG 작업 또는 SBERT 사용 시
                    log_entry["embedding_model_used"] = SBERT_MODEL_NAME
                
                log_entry.update(additional_log_data) # RAG 컨텍스트 등 추가 정보 병합

                try:
                    # 로그 디렉토리 생성은 ensure_directories에서 이미 수행됨
                    with open(LOG_FILENAME, 'a', encoding='utf-8') as f:
                        f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')
                except Exception as log_e:
                    print(f"[오류] 로그 파일 저장 실패: {log_e}")

        except SystemExit: # 초기화 실패 등 명시적 종료
            raise # 다시 발생시켜 main의 finally에서 처리하도록 함
        except KeyboardInterrupt: # 루프 내 Ctrl+C
            raise # 다시 발생
        except Exception as e: # 루프 내에서 발생한 그 외 모든 예외
            print(f"\n[!!! 작업 '{current_task_name}' 처리 중 오류 발생 !!!]")
            print(f"오류 상세: {type(e).__name__} - {e}")
            print("--- Traceback ---")
            traceback.print_exc()
            print("--- End Traceback ---")
            print("다음 작업을 계속 진행합니다.")
            # 오류 발생 시 해당 루프의 로깅은 자동으로 건너뜀 (log_this_run=False 설정 또는 위에서 처리)

if __name__ == "__main__":
    print(f"스크립트 시작: {datetime.datetime.now(datetime.timezone.utc).isoformat()}")
    
    try:
        ensure_directories() # 필수 디렉토리 확인 및 생성
        main_app_loop()      # 메인 애플리케이션 루프 실행
    except KeyboardInterrupt:
        print("\n[알림] 사용자에 의해 스크립트가 중단되었습니다.")
    except SystemExit as e: # 초기화 실패 등으로 인한 정상 종료
        print(f"프로그램 종료: {e}")
    except Exception as e: # 예상치 못한 최상위 예외
        print(f"\n[!!! 스크립트 실행 중 치명적인 글로벌 오류 발생 !!!]")
        print(f"오류 상세: {type(e).__name__} - {e}")
        traceback.print_exc()
    finally:
        print(f"\n스크립트 종료: {datetime.datetime.now(datetime.timezone.utc).isoformat()}")