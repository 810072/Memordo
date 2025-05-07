# config.py
import os

# --- 경로 설정 ---
BASE_DIR = os.path.dirname(os.path.abspath(os.path.join(__file__, os.pardir))) # 프로젝트 루트 디렉토리
DOC_DIR = os.path.join(BASE_DIR, "Doc")      # 문서 디렉토리
LOG_DIR = os.path.join(BASE_DIR, "log")      # 로그 디렉토리
CHROMA_DB_PATH = os.path.join(BASE_DIR, "chroma_db_st_google") # ChromaDB 저장 경로
LOG_FILENAME = os.path.join(LOG_DIR, "interaction_log_st_google.jsonl")

# --- API 및 모델 설정 ---
OLLAMA_API_URL = "http://localhost:11434/api/generate"
DEFAULT_OLLAMA_MODEL = "llama3.1:8b"

# --- SentenceTransformer 모델 설정 ---
SBERT_MODEL_NAME = 'all-MiniLM-L6-v2' # 영어 임베딩 모델

# --- ChromaDB 컬렉션 설정 ---
CHROMA_COLLECTION_NAME = "documents_ko_en_sbert"

# --- 기타 설정 ---
DEFAULT_TRANSLATION_RETRIES = 3
DEFAULT_TRANSLATION_DELAY = 1
OLLAMA_TIMEOUT = 180
CHUNK_SENTS_PER_CHUNK = 7 # 문서 인덱싱 시 청크 당 문장 수
RAG_TOP_N_CHUNKS = 3      # RAG 수행 시 가져올 상위 청크 수
INDEXING_BATCH_SIZE = 50  # 인덱싱 시 DB에 일괄 추가할 청크 수