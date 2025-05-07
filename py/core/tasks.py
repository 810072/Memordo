# core/tasks.py
import re
import json # comparison_task에서 로그 읽기 위해 필요
import os   # comparison_task에서 로그 파일 경로 위해 필요

# config에서 필요한 상수들을 가져옵니다. SBERT_MODEL_NAME 추가
from config import (
    DEFAULT_OLLAMA_MODEL, DOC_DIR, INDEXING_BATCH_SIZE,
    RAG_TOP_N_CHUNKS, LOG_FILENAME, SBERT_MODEL_NAME # SBERT_MODEL_NAME 추가
)
from utils.translator import translate_text
from utils.embedder import get_embedding_for_text_en
from utils.vector_db import add_embeddings_to_db, query_similar_embeddings, get_db_collection_count, get_db_entry_by_id
from utils.ollama_interface import query_ollama, execute_ollama_task
from utils.document_processor import get_document_paths, read_document_content, chunk_text_by_sentences
from prompts import task_prompts, create_adaptive_prompt


def perform_chat_task(user_input_ko, model=DEFAULT_OLLAMA_MODEL):
    """일반 대화 작업을 수행합니다."""
    english_prompt = translate_text(user_input_ko, 'ko', 'en')
    if english_prompt.startswith("Error"):
        return english_prompt # 번역 오류 반환
    return execute_ollama_task(english_prompt, model=model)


def perform_adaptive_task(user_input_ko, task_type, model=DEFAULT_OLLAMA_MODEL):
    """내용 유형 분석 후 적응형 프롬프트를 사용하여 Ollama 작업을 수행하고 결과를 반환합니다."""
    content_type = "unknown" # 기본 내용 유형

    # --- 1단계: 내용 유형 분석 ---
    try:
        print("[1단계] 내용 유형 분석 중...")
        # 분류 프롬프트 생성 (한국어 사용자 입력 포함)
        classify_prompt_template_en = task_prompts['classify'] # 영어 템플릿
        
        # [TEXT] 부분만 번역하여 삽입하거나, 전체 프롬프트를 번역할 수 있음.
        # 여기서는 [TEXT]를 영어로 번역하고, 영어 템플릿에 삽입.
        user_input_en_for_classify = translate_text(user_input_ko, 'ko', 'en')
        if user_input_en_for_classify.startswith("Error"):
            print(f"  [경고] 내용 분석용 입력 번역 실패: {user_input_en_for_classify}. 기본 프롬프트를 사용합니다.")
            # 이 경우 분류 없이 진행하거나, 오류로 처리할 수 있음. 여기서는 content_type='unknown' 유지.
        else:
            classify_prompt_en = classify_prompt_template_en.replace("[TEXT]", user_input_en_for_classify)
            
            classification_result_en = query_ollama(classify_prompt_en, model=model)

            if classification_result_en.startswith("Error"):
                print(f"  [경고] 내용 유형 분석 실패: {classification_result_en}. 기본 프롬프트를 사용합니다.")
            else:
                # Ollama 응답에서 유형 레이블만 추출 시도
                detected_type = classification_result_en.splitlines()[0].strip().lower()
                expected_types = ["meeting_notes", "idea_brainstorming", "technical_explanation",
                                  "personal_reflection", "todo_list", "general_information", "other"]
                if detected_type in expected_types:
                    content_type = detected_type
                    print(f"  감지된 내용 유형: {content_type}")
                elif detected_type: # 예상 목록에는 없지만 응답이 온 경우
                    print(f"  [정보] 예상치 못한 내용 유형 응답 '{detected_type}' 감지됨. 'other'로 처리합니다.")
                    content_type = "other"
                else: # 응답이 비어있거나 유효하지 않은 경우
                    print(f"  [경고] 내용 유형 분석 결과가 비어있거나 유효하지 않음. 기본 프롬프트를 사용합니다.")
    except Exception as e:
        print(f"  [경고] 내용 유형 분석 중 예외 발생: {type(e).__name__} - {e}. 기본 프롬프트를 사용합니다.")

    # --- 2단계: 적응형 프롬프트 생성 및 실행 ---
    try:
        print(f"[2단계] 내용 유형({content_type}) 기반 '{task_type}' 작업 실행 중...")
        final_english_prompt = create_adaptive_prompt(user_input_ko, task_type, content_type)
        # create_adaptive_prompt 내부에서 user_input_ko를 영어로 번역함.
        # 만약 번역 실패 시 Exception 발생.

        final_result_ko = execute_ollama_task(final_english_prompt, model=model)
        return final_result_ko
    except Exception as e:
        error_msg = f"적응형 작업({task_type}) 처리 중 오류 발생: {type(e).__name__} - {e}."
        print(f"  [오류] {error_msg}")
        print("[Fallback] 기본 프롬프트로 작업 재시도 중...")
        try:
            # 기본 프롬프트 템플릿 가져오기 (영어)
            default_prompt_template_en = task_prompts[task_type]
            # 사용자 입력 번역 (ko -> en)
            user_input_en_fallback = translate_text(user_input_ko, 'ko', 'en')
            if user_input_en_fallback.startswith("Error"):
                return f"오류: Fallback 시 사용자 입력 번역 실패 - {user_input_en_fallback}"

            default_prompt_en = default_prompt_template_en.replace("[TEXT]", user_input_en_fallback)
            fallback_result = execute_ollama_task(default_prompt_en, model=model)
            return fallback_result
        except Exception as fallback_e:
            return f"오류: Fallback 작업 실행 중 오류 발생 - {type(fallback_e).__name__} - {fallback_e}"


def perform_keyword_extraction(user_input_ko, model=DEFAULT_OLLAMA_MODEL):
    """키워드 추출 작업을 수행합니다."""
    user_input_en = translate_text(user_input_ko, 'ko', 'en')
    if user_input_en.startswith("Error"):
        return user_input_en, None # 번역 오류, 영어 결과 없음

    keyword_prompt_template_en = task_prompts["keyword"]
    english_prompt_for_kw = keyword_prompt_template_en.replace("[TEXT]", user_input_en)
    
    keyword_result_en = query_ollama(english_prompt_for_kw, model=model)

    if keyword_result_en.startswith("Error"):
        return keyword_result_en, keyword_result_en # 오류, 영어 결과는 오류 메시지

    # Ollama는 영어 키워드를 생성 (프롬프트 지시)
    # 사용자는 한국어로 결과를 보길 원할 수 있으므로, 번역 시도
    # 하지만 Comparison Task는 한국어 키워드를 기대하므로, 번역된 결과가 중요.
    keyword_result_ko = translate_text(keyword_result_en, 'en', 'ko')
    
    final_result = keyword_result_ko
    if keyword_result_ko.startswith("Error"):
        print(f"[Warning] 키워드 결과 한국어 번역 실패: {keyword_result_ko}. 영어 결과를 대신 사용합니다.")
        final_result = f"[en_keywords] {keyword_result_en}" # 로그 및 표시에 영어 결과 사용 명시
        # comparison_task가 한국어 키워드를 기대한다면, 이 경우 문제가 될 수 있음.
        # 이럴 때는 keyword_result_en 을 반환하고, 로깅 시 주의.

    return final_result, keyword_result_en # 최종 표시용 결과 (ko 또는 en), 원본 영어 키워드 결과


def perform_comparison(model=DEFAULT_OLLAMA_MODEL):
    """로그 파일에서 키워드 로그를 읽어 두 항목 간의 유사성을 비교합니다."""
    keyword_logs = []
    try:
        if not os.path.exists(LOG_FILENAME):
            return "[오류] 로그 파일을 찾을 수 없습니다. 키워드 추출(3번)을 먼저 수행하여 로그를 생성해주세요."

        with open(LOG_FILENAME, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    log_entry = json.loads(line)
                    # 'keyword' 작업 로그의 'output' 필드 (한국어 번역된 키워드) 사용
                    if log_entry.get('task') == 'keyword' and \
                       'output' in log_entry and \
                       isinstance(log_entry.get('output'), str) and \
                       ':' in log_entry['output'] and \
                       not log_entry['output'].startswith("Error:") and \
                       not log_entry['output'].startswith("[en_keywords]"): # 한국어 번역된 키워드만 사용 가정

                        display_name = f"텍스트: {log_entry.get('input', 'N/A')[:30]}..."

                        keyword_logs.append({
                            "timestamp": log_entry.get('timestamp', 'N/A'),
                            "name": display_name,
                            "output": log_entry['output'] # 한국어 키워드
                        })
                except (json.JSONDecodeError, KeyError, TypeError):
                    continue # 파싱 오류 무시
                except Exception as e: # 기타 오류
                    print(f"[경고] 로그 파일 '{LOG_FILENAME}'의 {line_num}번째 라인 처리 중 오류: {type(e).__name__}")
                    continue
    except FileNotFoundError:
        return "[오류] 로그 파일을 찾을 수 없습니다."
    except Exception as e:
        return f"[오류] 로그 파일 읽기 중 오류 발생: {e}"

    if len(keyword_logs) < 2:
        return f"[오류] 비교할 유효한 한국어 키워드 로그가 2개 이상 필요합니다. 현재 {len(keyword_logs)}개."

    print("\n--- 비교 가능한 키워드 로그 목록 (한국어 키워드 기반) ---")
    for i, log_data in enumerate(keyword_logs):
        print(f"{i+1}. [{log_data['timestamp']}] {log_data['name']}")
    print("-------------------------------------------------------")

    selected_indices = []
    while len(selected_indices) < 2:
        try:
            prompt_msg = f"비교할 {'첫' if not selected_indices else '두'} 번째 로그 번호 (1-{len(keyword_logs)}): "
            choice_str = input(prompt_msg).strip()
            if not choice_str: continue
            choice_num = int(choice_str)
            selected_index = choice_num - 1 # 실제 리스트 인덱스로 변환

            if 0 <= selected_index < len(keyword_logs):
                if selected_index not in selected_indices:
                    selected_indices.append(selected_index)
                else:
                    print("[오류] 이미 선택한 로그입니다. 다른 번호를 입력해주세요.")
            else:
                print(f"[오류] 1에서 {len(keyword_logs)} 사이의 번호를 입력해주세요.")
        except ValueError:
            print("[오류] 유효한 숫자를 입력해주세요.")
        except EOFError: # Ctrl+D 등으로 입력 종료 시
            print("\n입력이 중단되었습니다.")
            return "[알림] 사용자 입력 중단됨."

    log1 = keyword_logs[selected_indices[0]]
    log2 = keyword_logs[selected_indices[1]]
    keywords1_ko = log1['output'] # 한국어 키워드
    keywords2_ko = log2['output'] # 한국어 키워드
    name1 = log1['name']
    name2 = log2['name']

    print(f"\n--- 선택된 비교 대상 ---")
    print(f"1: {name1}")
    print(f"2: {name2}")
    print("-------------------------")

    try:
        # 비교 프롬프트는 영어로 되어 있고, 한국어 키워드를 영어로 번역하여 삽입해야 할 수도 있음.
        # 또는, 프롬프트 자체를 한국어로 수정하고, 최종적으로 Ollama에 영어로 번역 전달.
        # 현재 프롬프트는 영어 키워드를 가정하는 것처럼 보이기도 함.
        # 여기서는 한국어 키워드를 직접 사용하고, 전체 비교 프롬프트를 영어로 번역.
        comparison_prompt_template_ko = task_prompts["comparison"] # 영어 템플릿이지만, 키워드 부분은 한국어
        comparison_prompt_with_ko_keywords = comparison_prompt_template_ko.replace("[KEYWORDS1]", keywords1_ko)
        comparison_prompt_with_ko_keywords = comparison_prompt_with_ko_keywords.replace("[KEYWORDS2]", keywords2_ko)
        
        # 전체 비교 요청을 영어로 번역
        comparison_prompt_en = translate_text(comparison_prompt_with_ko_keywords, 'ko', 'en')
        if comparison_prompt_en.startswith("Error"):
            raise Exception(f"Comparison 프롬프트 번역 실패: {comparison_prompt_en}")

        print(f"\n[comparison] 작업을 Ollama({model})에게 요청합니다...")
        comparison_result_en = query_ollama(comparison_prompt_en, model=model) # 결과는 영어 점수 텍스트 예상

        if comparison_result_en.startswith("Error"):
            return f"[오류] 유사성 평가 중 오류 발생: {comparison_result_en}"

        # 결과에서 숫자 점수만 추출 시도 (번역 불필요)
        try:
            score_text = comparison_result_en.strip()
            match = re.search(r"(\d*\.\d+|\d+)", score_text) # 소수점 포함 숫자
            if match:
                score = float(match.group(1))
                if 0.0 <= score <= 1.0:
                    return f"'{name1}'와(과) '{name2}' 간의 키워드 기반 유사성 점수: {score:.2f}"
                else:
                    return f"계산된 유사성 점수 ({score:.2f})가 범위(0-1)를 벗어났습니다. 원본 결과: '{score_text}'"
            else: # 숫자 못 찾으면 원본 반환
                return f"유사성 평가 결과 (점수 추출 불가): '{score_text}'"
        except ValueError: # float 변환 실패 시
            return f"유사성 평가 결과 (텍스트, 점수 변환 불가): '{comparison_result_en}'"
    except Exception as e:
        return f"[오류] Comparison 작업 처리 중 문제 발생: {type(e).__name__} - {e}"


def perform_indexing(doc_dir_path=DOC_DIR, batch_size=INDEXING_BATCH_SIZE):
    """문서들을 읽어 청킹, 번역, 임베딩 후 벡터 DB에 저장합니다."""
    print(f"\n--- '{doc_dir_path}' 내 .md 파일 벡터 인덱싱 시작 ---")
    doc_paths = get_document_paths(doc_dir_path)
    if not doc_paths:
        print("인덱싱할 .md 파일이 없습니다.")
        return

    total_files = len(doc_paths)
    indexed_file_count = 0
    error_file_count = 0
    total_chunks_processed_in_run = 0

    for file_idx, filepath in enumerate(doc_paths, 1):
        filepath_str = str(filepath)
        print(f"\n  ({file_idx}/{total_files}) 파일 처리 중: {filepath.name}")

        content_ko = read_document_content(filepath)
        if content_ko is None or not content_ko.strip():
            print(f"    - 내용을 읽을 수 없거나 비어있어 건너<0xEB><0x84>니다.")
            error_file_count += 1
            continue

        text_chunks_ko = chunk_text_by_sentences(content_ko) # sentences_per_chunk는 config에서 가져옴
        if not text_chunks_ko:
            print(f"    - 텍스트 청킹 결과가 없어 건너<0xEB><0x84>니다.")
            error_file_count += 1
            continue
        
        print(f"    - 원본 한국어 문서 청크 수: {len(text_chunks_ko)}")

        chunk_embeddings_batch = []
        chunk_metadatas_batch = []
        chunk_ids_batch = []
        processed_chunks_for_this_file_successfully = 0

        for chunk_idx, chunk_ko in enumerate(text_chunks_ko):
            chunk_id_str = f"{filepath_str}_chunk_{chunk_idx}"

            existing_entry = get_db_entry_by_id(chunk_id_str) # utils.vector_db 사용
            if existing_entry and existing_entry['ids'] and chunk_id_str in existing_entry['ids']:
                # print(f"      - 청크 ID '{chunk_id_str}'는 이미 DB에 존재하여 건너<0xEB><0x84>니다.")
                continue # 이미 처리된 청크

            chunk_en = translate_text(chunk_ko, 'ko', 'en')
            if chunk_en.startswith("Error:") or not chunk_en.strip():
                print(f"      - 청크 {chunk_idx + 1} 번역 실패. 건너<0xEB><0x84>니다.")
                continue
            
            embedding = get_embedding_for_text_en(chunk_en)
            if embedding is None:
                print(f"      - 청크 {chunk_idx + 1} 임베딩 생성 실패. 건너<0xEB><0x84>니다.")
                continue

            chunk_embeddings_batch.append(embedding)
            chunk_metadatas_batch.append({
                "source_filepath": filepath_str,
                "filename": filepath.name,
                "chunk_id_in_doc": chunk_idx,
                "original_text_ko": chunk_ko,
                "translated_text_en": chunk_en
            })
            chunk_ids_batch.append(chunk_id_str)
            
            if len(chunk_ids_batch) >= batch_size:
                if add_embeddings_to_db(chunk_embeddings_batch, chunk_metadatas_batch, chunk_ids_batch):
                    print(f"      - {len(chunk_ids_batch)}개 청크 묶음 DB에 추가 완료.")
                    processed_chunks_for_this_file_successfully += len(chunk_ids_batch)
                else:
                    print(f"      - {len(chunk_ids_batch)}개 청크 묶음 DB 추가 실패.")
                chunk_embeddings_batch, chunk_metadatas_batch, chunk_ids_batch = [], [], [] # 리스트 초기화
        
        # 남은 청크들 저장
        if chunk_ids_batch:
            if add_embeddings_to_db(chunk_embeddings_batch, chunk_metadatas_batch, chunk_ids_batch):
                print(f"      - 남은 {len(chunk_ids_batch)}개 청크 DB에 추가 완료.")
                processed_chunks_for_this_file_successfully += len(chunk_ids_batch)
            else:
                print(f"      - 남은 {len(chunk_ids_batch)}개 청크 DB 추가 실패.")
        
        if processed_chunks_for_this_file_successfully > 0:
            indexed_file_count += 1
            total_chunks_processed_in_run += processed_chunks_for_this_file_successfully
            print(f"    - 파일 '{filepath.name}'에서 {processed_chunks_for_this_file_successfully}개 청크 처리 완료.")
        elif not any(get_db_entry_by_id(f"{filepath_str}_chunk_{i}")['ids'] for i in range(len(text_chunks_ko)) if get_db_entry_by_id(f"{filepath_str}_chunk_{i}")):
            error_file_count += 1
            print(f"    - 파일 '{filepath.name}' 처리 중 유효한 청크를 DB에 저장하지 못했습니다.")

    print(f"\n--- 벡터 인덱싱 완료 ---")
    print(f"  처리 시도한 총 파일 수: {total_files}")
    print(f"  성공적으로 일부라도 인덱싱된 파일 수: {indexed_file_count}")
    print(f"  오류 발생 파일 수: {error_file_count}")
    print(f"  이번 실행에서 DB에 추가된 총 청크 수: {total_chunks_processed_in_run}")
    print(f"  현재 DB의 총 아이템(청크) 수: {get_db_collection_count()}")


def perform_rag_query(user_query_ko, model=DEFAULT_OLLAMA_MODEL, top_n_chunks=RAG_TOP_N_CHUNKS):
    """벡터 DB 검색 기반 RAG 작업을 수행합니다."""
    print(f"\n--- 벡터 기반 관련 문서 검색 및 응답 생성 시작 (쿼리: '{user_query_ko[:30]}...') ---")
    
    # 1. 한국어 쿼리 -> 영어로 번역
    query_en = translate_text(user_query_ko, 'ko', 'en')
    if query_en.startswith("Error:") or not query_en.strip():
        error_msg = f"[오류] RAG 쿼리 번역 실패: {query_en}"
        print(error_msg)
        return error_msg, {} # 결과, 로그메타데이터
    print(f"  번역된 영어 쿼리: '{query_en[:50]}...'")

    # 2. 번역된 영어 쿼리 -> 임베딩 생성
    query_embedding = get_embedding_for_text_en(query_en)
    if query_embedding is None:
        error_msg = "[오류] RAG 쿼리 임베딩 생성에 실패했습니다."
        print(error_msg)
        return error_msg, {}

    # 3. 벡터 DB에서 유사도 검색
    db_results = query_similar_embeddings(query_embedding, top_n=top_n_chunks) # utils.vector_db 사용

    # SBERT_MODEL_NAME은 config.py에서 import 되어야 함 (파일 상단에 추가됨)
    log_metadata_rag = {"sbert_model_for_rag": SBERT_MODEL_NAME} 

    if not db_results or not db_results.get('ids') or not db_results.get('ids')[0]:
        print("[알림] RAG: 유사한 문서를 찾지 못했습니다. 일반 Chat 방식으로 Fallback 합니다.")
        # Fallback 로직은 main.py에서 호출하여 처리하거나 여기서 직접 처리
        # 여기서는 Fallback 상황임을 알리는 메시지와 함께 일반 chat 결과 반환
        log_metadata_rag['rag_fallback_reason'] = "No similar documents found"
        chat_result = perform_chat_task(user_query_ko, model) # 일반 챗 태스크 호출
        return chat_result, log_metadata_rag

    # 4. 검색된 영어 컨텍스트를 활용하여 Ollama에 전달할 최종 프롬프트(영어) 구성
    print("--- RAG: 관련 정보 기반 응답 생성 중 ---")
    
    augmented_context_en_str = ""
    retrieved_sources_for_log = []
    
    # ChromaDB 결과 구조에 맞춰 파싱
    ids_list = db_results.get('ids')[0]
    metadatas_list = db_results.get('metadatas')[0]
    distances_list = db_results.get('distances')[0]

    for i in range(len(ids_list)):
        meta = metadatas_list[i]
        filename = meta.get('filename', 'N/A')
        # 컨텍스트로 사용할 영어 청크 (DB 저장 시 translated_text_en 으로 저장)
        context_en_chunk = meta.get('translated_text_en', '') 
        original_ko_chunk_preview = meta.get('original_text_ko', '')[:100] + "..."
        score = 1 - distances_list[i] # 거리 -> 유사도

        augmented_context_en_str += f"\n--- Relevant English Context {i+1} (Source: {filename}, Similarity: {score:.4f}) ---\n"
        augmented_context_en_str += context_en_chunk + "\n"
        retrieved_sources_for_log.append({
            "id": ids_list[i],
            "filename": filename,
            "original_ko_chunk_preview": original_ko_chunk_preview,
            "retrieved_en_context_preview": context_en_chunk[:100] + "...",
            "score": score
        })
    log_metadata_rag['retrieved_contexts'] = retrieved_sources_for_log

    # 최종 영어 프롬프트: 영어 질문 + 영어 컨텍스트 + 한국어 답변 유도 지시
    # 사용자 질문(영어)은 이미 query_en으로 번역됨
    # 수정된 프롬프트 (사용자 제공 코드 기반)
    final_rag_prompt_en = f""" "{query_en}"

Please use the following English context

{augmented_context_en_str}

"""
    
    print(f"  Ollama에 전달될 RAG 프롬프트 (일부): {final_rag_prompt_en[:3000]}...") # 길이 제한 3000으로 증가
    
    result_ko = execute_ollama_task(final_rag_prompt_en, model=model)
    return result_ko, log_metadata_rag