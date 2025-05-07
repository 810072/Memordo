1. config.py
파일 목적/역할:

프로젝트 전체에서 사용되는 주요 설정값 및 상수들을 중앙에서 관리합니다.
API URL, 기본 모델 이름, 파일 시스템 경로, 로깅 설정, 임베딩 모델 이름, ChromaDB 컬렉션 이름 등 변경 가능성이 있거나 여러 모듈에서 공유해야 하는 값들을 정의합니다.
설정 변경 시 이 파일만 수정하면 되므로 유지보수성이 향상됩니다.
주요 내용:

경로 설정: BASE_DIR, DOC_DIR, LOG_DIR, CHROMA_DB_PATH, LOG_FILENAME 등 파일 시스템 경로를 정의합니다. BASE_DIR는 프로젝트의 루트 디렉토리를 가리킵니다.
API 및 모델 설정: OLLAMA_API_URL, DEFAULT_OLLAMA_MODEL (Ollama LLM 관련), SBERT_MODEL_NAME (SentenceTransformer 임베딩 모델 관련)을 정의합니다.
ChromaDB 설정: CHROMA_COLLECTION_NAME을 정의합니다.
기타 설정: DEFAULT_TRANSLATION_RETRIES, DEFAULT_TRANSLATION_DELAY (번역 시도 횟수 및 딜레이), OLLAMA_TIMEOUT (Ollama API 타임아웃), CHUNK_SENTS_PER_CHUNK (문서 청킹 시 문장 수), RAG_TOP_N_CHUNKS (RAG 수행 시 검색할 청크 수), INDEXING_BATCH_SIZE (인덱싱 시 DB 일괄 추가 크기) 등을 정의합니다.
사용법:

다른 파일에서는 from config import VARIABLE_NAME 형태로 필요한 설정값을 가져와 사용합니다.
Python

from config import DEFAULT_OLLAMA_MODEL, DOC_DIR
print(f"기본 LLM 모델: {DEFAULT_OLLAMA_MODEL}")
외부 의존성:

os (파일 경로 구성을 위해)
2. prompts.py
파일 목적/역할:

Ollama LLM에 전달될 다양한 작업별 프롬프트 템플릿을 관리합니다.
내용 유형에 따라 동적으로 프롬프트를 조정하는 함수를 제공합니다.
주요 기능/함수 설명:

task_prompts (딕셔셔너리):
설명: classify, summarize, memo, keyword, comparison 등 각 작업 유형에 대한 기본 프롬프트 템플릿을 문자열 형태로 저장합니다. 템플릿 내에는 [TEXT], [KEYWORDS1] 등 실제 내용으로 대체될 플레이스홀더가 포함될 수 있습니다.
사용법: prompts.task_prompts['summarize'] 와 같이 특정 작업의 템플릿을 가져올 수 있습니다.
create_adaptive_prompt(user_input_ko, task_type, content_type):
설명: 사용자의 한국어 입력(user_input_ko), 작업 유형(task_type), 그리고 (선택적으로) 분석된 내용 유형(content_type)을 기반으로 최적화된 프롬프트를 생성합니다.
내부적으로 user_input_ko를 영어로 번역하고, content_type에 따라 task_prompts의 기본 템플릿을 수정하거나 선택하여 최종 영어 프롬프트를 반환합니다.
번역 실패 또는 부적절한 task_type 시 예외를 발생시키거나 경고를 출력할 수 있습니다.
입력:
user_input_ko (str): 사용자가 입력한 원본 한국어 텍스트.
task_type (str): 수행할 작업의 종류 (예: "summarize", "memo").
content_type (str): (선택적) 분석된 내용의 유형 (예: "meeting_notes").
출력: (str) LLM에 전달될 최종 영어 프롬프트 또는 번역 실패 시 오류 메시지.
사용법:
Python

from prompts import create_adaptive_prompt
try:
    prompt = create_adaptive_prompt("오늘 회의 내용을 요약해줘.", "summarize", "meeting_notes")
    # prompt를 Ollama에 전달
except Exception as e:
    print(f"프롬프트 생성 오류: {e}")
외부 의존성:

utils.translator.translate_text (프롬프트 내 사용자 입력 및 전체 프롬프트 번역에 사용)
3. utils/__init__.py
파일 목적/역할:
utils 디렉토리를 파이썬 패키지로 만들어줍니다.
이 파일이 존재함으로써 from utils.module_name import function_name과 같은 형태로 utils 패키지 내의 모듈들을 임포트할 수 있게 됩니다.
(선택 사항) 패키지 레벨에서 자주 사용되는 함수들을 이 파일에 미리 임포트하여 from utils import commonly_used_function 형태로 더 짧게 사용할 수 있도록 할 수 있습니다. 현재 코드에서는 비어 있습니다.
4. utils/translator.py
파일 목적/역할:

텍스트 번역과 관련된 유틸리티 함수를 제공합니다.
주로 googletrans 라이브러리를 사용하여 텍스트의 언어를 감지하고, 한 언어에서 다른 언어로 번역하는 기능을 수행합니다.
주요 기능/함수 설명:

detect_language(text):
설명: 입력된 텍스트의 언어를 감지하여 언어 코드(예: 'ko', 'en')를 반환합니다.
입력: text (str) - 언어를 감지할 텍스트.
출력: (str) 감지된 언어 코드 또는 감지 실패 시 None.
사용법: lang_code = detect_language("안녕하세요")
translate_text(text, src_lang, dest_lang, retries=DEFAULT_TRANSLATION_RETRIES, delay=DEFAULT_TRANSLATION_DELAY):
설명: 주어진 텍스트를 소스 언어(src_lang)에서 목적 언어(dest_lang)로 번역합니다. src_lang에 'auto'를 지정하면 언어를 자동으로 감지합니다. 네트워크 오류 등을 대비하여 재시도 로직이 포함되어 있습니다.
입력:
text (str): 번역할 텍스트.
src_lang (str): 소스 언어 코드 (예: 'ko', 'en', 'auto').
dest_lang (str): 목적 언어 코드 (예: 'en', 'ko').
retries (int): 실패 시 재시도 횟수.
delay (int): 재시도 간 기본 대기 시간(초).
출력: (str) 번역된 텍스트 또는 오류 발생 시 "Error: ..." 형태의 메시지.
사용법: translated = translate_text("안녕하세요", 'ko', 'en')
외부 의존성:

googletrans.Translator, googletrans.LANGUAGES
requests.exceptions.RequestException
httpx (타임아웃 설정 시 사용 가능)
time (재시도 딜레이)
traceback (오류 로깅)
config.DEFAULT_TRANSLATION_RETRIES, config.DEFAULT_TRANSLATION_DELAY
5. utils/embedder.py
파일 목적/역할:

텍스트 임베딩 생성과 관련된 기능을 제공합니다.
주로 sentence-transformers 라이브러리를 사용하여 영어 텍스트를 고정 크기의 숫자 벡터(임베딩)로 변환합니다.
주요 기능/함수 설명:

SBERT_MODEL (전역 변수): 로드된 SentenceTransformer 모델 객체를 저장하여 재사용합니다. 초기값은 None입니다.
get_sbert_model():
설명: SBERT_MODEL이 아직 로드되지 않았다면 config.SBERT_MODEL_NAME에 지정된 모델을 로드하여 SBERT_MODEL 변수에 할당하고 반환합니다. 이미 로드되었다면 저장된 객체를 즉시 반환합니다. 모델 로드 실패 시 SystemExit 예외를 발생시켜 프로그램 실행을 중단시킵니다.
입력: 없음.
출력: 로드된 SentenceTransformer 모델 객체.
사용법: model = get_sbert_model()
get_embedding_for_text_en(text_en):
설명: 입력된 영어 텍스트(text_en)에 대해 get_sbert_model()을 통해 얻은 모델을 사용하여 임베딩 벡터를 생성합니다. 생성된 벡터는 리스트 형태로 반환됩니다 (ChromaDB 저장 용이).
입력: text_en (str) - 임베딩을 생성할 영어 텍스트.
출력: (list of float) 생성된 임베딩 벡터 또는 오류 발생 시 None.
사용법: embedding_vector = get_embedding_for_text_en("This is an English sentence.")
외부 의존성:

sentence_transformers.SentenceTransformer
config.SBERT_MODEL_NAME
traceback (오류 로깅)
6. utils/vector_db.py
파일 목적/역할:

벡터 데이터베이스(ChromaDB)와의 상호작용을 담당합니다.
DB 클라이언트 및 컬렉션 초기화, 임베딩 데이터 추가, 유사도 기반 검색 등의 기능을 제공합니다.
주요 기능/함수 설명:

CHROMA_CLIENT, CHROMA_COLLECTION (전역 변수): 초기화된 ChromaDB 클라이언트 및 컬렉션 객체를 저장합니다.
initialize_chromadb():
설명: CHROMA_CLIENT와 CHROMA_COLLECTION이 아직 초기화되지 않았다면, config.CHROMA_DB_PATH를 사용하여 디스크 기반의 PersistentClient를 생성하고, config.CHROMA_COLLECTION_NAME으로 컬렉션을 가져오거나 생성합니다. 초기화 실패 시 SystemExit 예외를 발생시킵니다.
입력: 없음.
출력: 초기화/로드된 ChromaDB 컬렉션 객체.
사용법: collection = initialize_chromadb() (주로 다른 함수 내부에서 호출됨)
add_embeddings_to_db(embeddings, metadatas, ids):
설명: 주어진 임베딩 벡터 리스트, 메타데이터 리스트, ID 리스트를 ChromaDB 컬렉션에 추가합니다. 모든 리스트의 길이는 동일해야 합니다.
입력:
embeddings (list of list of float): 추가할 임베딩 벡터들의 리스트.
metadatas (list of dict): 각 임베딩에 해당하는 메타데이터들의 리스트.
ids (list of str): 각 임베딩에 대한 고유 ID들의 리스트.
출력: (bool) 작업 성공 여부.
사용법: success = add_embeddings_to_db([vec1, vec2], [meta1, meta2], [id1, id2])
query_similar_embeddings(query_embedding, top_n=3):
설명: 주어진 쿼리 임베딩과 유사한 항목들을 ChromaDB 컬렉션에서 검색합니다. 상위 top_n개의 결과를 반환합니다.
입력:
query_embedding (list of float): 검색의 기준이 될 쿼리 임베딩 벡터.
top_n (int): 반환할 유사 항목의 최대 개수.
출력: (dict or None) ChromaDB의 검색 결과 객체 (ID, 메타데이터, 거리 등 포함) 또는 오류 시 None.
사용법: results = query_similar_embeddings(query_vec, top_n=5)
get_db_collection_count():
설명: 현재 DB 컬렉션에 저장된 아이템(청크)의 총 개수를 반환합니다.
출력: (int) 아이템 수.
get_db_entry_by_id(entry_id):
설명: 주어진 ID에 해당하는 DB 항목을 가져옵니다.
입력: entry_id (str) - 가져올 항목의 ID.
출력: (dict or None) ChromaDB의 get 결과 객체 또는 ID가 없거나 오류 시 None.
외부 의존성:

chromadb
os (DB 경로 생성)
config.CHROMA_DB_PATH, config.CHROMA_COLLECTION_NAME
traceback (오류 로깅)
7. utils/ollama_interface.py
파일 목적/역할:

로컬에서 실행 중인 Ollama LLM과의 통신을 담당합니다.
Ollama API에 프롬프트를 보내고 응답을 받아 처리하는 함수를 제공합니다.
주요 기능/함수 설명:

query_ollama(prompt, model=DEFAULT_OLLAMA_MODEL, url=OLLAMA_API_URL, timeout=OLLAMA_TIMEOUT):
설명: 주어진 프롬프트(prompt)를 지정된 Ollama 모델(model)에 전달하고, API의 원시 응답 텍스트를 반환합니다.
입력:
prompt (str): LLM에 전달할 프롬프트.
model (str): 사용할 Ollama 모델 이름.
url (str): Ollama API 엔드포인트 URL.
timeout (int): API 요청 타임아웃 시간(초).
출력: (str) LLM의 응답 텍스트 또는 오류 발생 시 "Error: ..." 형태의 메시지.
사용법: response_text = query_ollama("What is the capital of France?")
execute_ollama_task(english_prompt, model=DEFAULT_OLLAMA_MODEL):
설명: 영어 프롬프트(english_prompt)를 query_ollama를 통해 Ollama에 전달하고, 받은 (예상되는) 영어 응답을 다시 utils.translator.translate_text를 사용하여 한국어로 번역하여 최종 결과를 반환합니다.
입력:
english_prompt (str): Ollama에 전달할 영어 프롬프트.
model (str): 사용할 Ollama 모델 이름.
출력: (str) 최종 한국어 번역 결과 또는 오류 메시지.
사용법: korean_answer = execute_ollama_task("Summarize this text: ...")
외부 의존성:

requests (HTTP 요청)
json (JSON 처리)
traceback (오류 로깅)
config.OLLAMA_API_URL, config.DEFAULT_OLLAMA_MODEL, config.OLLAMA_TIMEOUT
utils.translator.translate_text (결과 번역)
8. utils/document_processor.py
파일 목적/역할:

로컬 파일 시스템의 문서 처리와 관련된 유틸리티 함수를 제공합니다.
지정된 디렉토리에서 문서 파일 경로를 찾고, 파일 내용을 읽으며, 텍스트를 적절한 크기의 청크로 나누는 기능을 수행합니다.
주요 기능/함수 설명:

get_document_paths(doc_dir):
설명: 주어진 디렉토리 경로(doc_dir)와 그 하위 디렉토리에서 모든 마크다운(.md) 파일의 경로를 찾아 리스트로 반환합니다.
입력: doc_dir (str) - 문서를 검색할 디렉토리 경로.
출력: (list of Path) 찾은 .md 파일들의 Path 객체 리스트.
사용법: md_files = get_document_paths("./MyDocuments")
read_document_content(filepath):
설명: 주어진 파일 경로(filepath)의 내용을 읽어 UTF-8 인코딩으로 문자열을 반환합니다.
입력: filepath (str or Path) - 읽을 파일의 경로.
출력: (str or None) 파일 내용 문자열 또는 파일 읽기 실패 시 None.
사용법: content = read_document_content("path/to/file.md")
chunk_text_by_sentences(text, sentences_per_chunk=CHUNK_SENTS_PER_CHUNK):
설명: 입력된 텍스트를 문장 단위로 나누고, 지정된 sentences_per_chunk 개수만큼의 문장들을 묶어 하나의 청크로 만듭니다. 현재는 간단한 구분자('.!?'\n') 기반으로 문장을 분리합니다. (더 정교한 분리는 nltk 등 외부 라이브러리 사용 고려)
입력:
text (str): 청킹할 원본 텍스트.
sentences_per_chunk (int): 하나의 청크에 포함될 문장의 수. config.CHUNK_SENTS_PER_CHUNK에서 기본값을 가져옵니다.
출력: (list of str) 생성된 텍스트 청크들의 리스트.
사용법: chunks = chunk_text_by_sentences(my_text, sentences_per_chunk=5)
외부 의존성:

pathlib.Path
config.CHUNK_SENTS_PER_CHUNK
9. core/__init__.py
파일 목적/역할:
core 디렉토리를 파이썬 패키지로 만들어줍니다.
utils/__init__.py와 마찬가지로 from core.module_name import function_name 형태로 core 패키지 내의 모듈들을 임포트할 수 있게 합니다. 현재 코드에서는 비어 있습니다.
10. core/tasks.py
파일 목적/역할:

애플리케이션의 주요 고수준 작업(비즈니스 로직)들을 함수 형태로 정의합니다.
main.py에서 사용자 요청에 따라 호출되며, 다양한 utils 모듈의 함수들을 조합하여 특정 작업을 완료합니다. 예를 들어, 문서 인덱싱, RAG 기반 질의응답, 키워드 추출 등의 복합적인 기능을 수행합니다.
주요 기능/함수 설명:

perform_chat_task(user_input_ko, model=DEFAULT_OLLAMA_MODEL):
설명: 사용자의 한국어 입력을 받아 번역 후 Ollama에 일반 대화형으로 질의하고, 그 결과를 다시 한국어로 번역하여 반환합니다.
사용법: response = perform_chat_task("오늘 날씨 어때?")
perform_adaptive_task(user_input_ko, task_type, model=DEFAULT_OLLAMA_MODEL):
설명: 입력 텍스트의 유형을 먼저 분석한 후, 해당 유형에 최적화된 (동적으로 생성된) 프롬프트를 사용하여 요약, 메모 등의 작업을 수행합니다. prompts.create_adaptive_prompt와 utils.ollama_interface.execute_ollama_task를 활용합니다.
사용법: summary = perform_adaptive_task("회의록입니다...", "summarize")
perform_keyword_extraction(user_input_ko, model=DEFAULT_OLLAMA_MODEL):
설명: 한국어 입력을 영어로 번역 후, 키워드 추출용 프롬프트를 사용하여 Ollama로부터 영어 키워드 및 점수를 추출합니다. 최종적으로 사용자에게 보여줄 결과(주로 한국어 번역된 키워드)와 원본 영어 키워드 결과를 함께 반환합니다 (로깅용).
출력: (final_result_for_display, original_english_keywords) 튜플.
사용법: korean_keywords, english_keywords = perform_keyword_extraction("이 문서의 핵심 내용을 알려줘.")
perform_comparison(model=DEFAULT_OLLAMA_MODEL):
설명: LOG_FILENAME에 기록된 'keyword' 작업 로그들 중 사용자가 두 개를 선택하면, 해당 로그에 저장된 (주로 한국어) 키워드들을 기반으로 Ollama에 유사도 평가를 요청하고 그 점수를 반환합니다.
사용법: comparison_score_text = perform_comparison() (내부적으로 사용자 입력 처리)
perform_indexing(doc_dir_path=DOC_DIR, batch_size=INDEXING_BATCH_SIZE):
설명: 지정된 디렉토리(doc_dir_path) 내의 .md 파일들을 대상으로 문서 인덱싱을 수행합니다. 각 문서는 청킹 -> 한국어 청크를 영어로 번역 -> 번역된 영어 청크를 SentenceTransformer로 임베딩 -> 생성된 벡터와 메타데이터를 ChromaDB에 저장하는 과정을 거칩니다. config.INDEXING_BATCH_SIZE만큼 모아서 DB에 일괄 추가합니다.
사용법: perform_indexing()
perform_rag_query(user_query_ko, model=DEFAULT_OLLAMA_MODEL, top_n_chunks=RAG_TOP_N_CHUNKS):
설명: Retrieval Augmented Generation (RAG) 작업을 수행합니다.
사용자의 한국어 질의(user_query_ko)를 영어로 번역합니다.
번역된 영어 질의를 임베딩합니다.
생성된 쿼리 벡터로 ChromaDB에서 유사한 문서 청크(top_n_chunks 개수만큼)를 검색합니다. 검색된 청크의 메타데이터에는 번역된 영어 텍스트(translated_text_en)와 원본 한국어 텍스트(original_text_ko)가 포함됩니다.
검색된 영어 청크 텍스트들을 컨텍스트로, 번역된 영어 질의를 질문으로 하여 Ollama LLM에 전달할 최종 영어 프롬프트를 구성합니다. (프롬프트는 LLM이 한국어로 답변하도록 유도합니다.)
Ollama의 응답을 받아 한국어로 번역하여 반환합니다.
유사 문서를 찾지 못하면 일반 채팅 방식으로 Fallback합니다.
출력: (final_korean_response, log_metadata_for_rag) 튜플.
사용법: answer, rag_log = perform_rag_query("우리 회사 제품 A의 주요 특징은 뭐야?")
외부 의존성:

config 모듈 (각종 설정값)
utils.translator
utils.embedder
utils.vector_db
utils.ollama_interface
utils.document_processor
prompts 모듈
re, json, os (일부 함수 내부에서 사용)
11. main.py
파일 목적/역할:

애플리케이션의 주 진입점(entry point)이자 실행 루프입니다.
사용자에게 명령줄 인터페이스(CLI) 메뉴를 제공하여 수행할 작업을 선택받습니다.
선택된 작업에 따라 core.tasks 모듈의 해당 함수를 호출하고, 그 결과를 사용자에게 보여주거나 필요한 로깅을 수행합니다.
스크립트 시작 시 필요한 초기화 작업(디렉토리 생성, 모델 로드, DB 클라이언트 초기화)을 수행합니다.
주요 기능/함수 설명:

ensure_directories():
설명: 로그, 문서, ChromaDB 저장 경로 등 프로젝트 실행에 필요한 디렉토리들이 존재하는지 확인하고, 없으면 생성합니다.
main_app_loop():
설명: 메인 애플리케이션의 무한 루프를 실행합니다.
시작 시 utils.embedder.get_sbert_model()과 utils.vector_db.initialize_chromadb()를 호출하여 SBERT 모델과 ChromaDB를 초기화합니다. 실패 시 프로그램이 종료될 수 있습니다.
사용자에게 작업 선택 메뉴를 반복적으로 보여줍니다.
사용자 선택에 따라 task_mapping을 참조하여 core.tasks의 적절한 함수를 호출합니다.
작업 수행 결과를 받아 사용자에게 출력합니다.
선택적으로 작업 내용(입력, 출력, 사용된 모델 등)을 config.LOG_FILENAME에 JSONL 형식으로 로깅합니다. (인덱싱, 비교 작업 등 일부 작업은 자체 메시지를 출력하거나 로깅 방식이 다를 수 있음)
각 작업 루프 내에서 발생하는 예외를 처리하여 프로그램이 갑자기 중단되는 것을 방지하려고 시도합니다.
if __name__ == "__main__": 블록:
설명: 스크립트가 직접 실행될 때 가장 먼저 실행되는 부분입니다.
스크립트 시작/종료 메시지를 출력하고, ensure_directories() 호출 후 main_app_loop()를 실행합니다.
KeyboardInterrupt (Ctrl+C)나 SystemExit (초기화 실패 등) 같은 최상위 예외를 처리하여 안전하게 종료될 수 있도록 합니다.
외부 의존성:

datetime, json, os, traceback (표준 라이브러리)
config 모듈 (모든 설정값)
utils.embedder.get_sbert_model
utils.vector_db.initialize_chromadb
core.tasks 모듈의 모든 perform_... 함수들