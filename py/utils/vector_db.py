# utils/vector_db.py
import chromadb
import os
from config import CHROMA_DB_PATH, CHROMA_COLLECTION_NAME
import traceback

CHROMA_CLIENT = None
CHROMA_COLLECTION = None

def initialize_chromadb():
    global CHROMA_CLIENT, CHROMA_COLLECTION
    if CHROMA_CLIENT is None:
        try:
            os.makedirs(CHROMA_DB_PATH, exist_ok=True)
            CHROMA_CLIENT = chromadb.PersistentClient(path=CHROMA_DB_PATH)
            print(f"ChromaDB 클라이언트 초기화 완료 (저장 경로: {CHROMA_DB_PATH})")
        except Exception as e:
            print(f"[치명적 오류] ChromaDB 클라이언트 초기화 실패: {e}")
            raise SystemExit(f"ChromaDB 클라이언트 초기화 실패: {e}")

    if CHROMA_COLLECTION is None and CHROMA_CLIENT:
        try:
            CHROMA_COLLECTION = CHROMA_CLIENT.get_or_create_collection(name=CHROMA_COLLECTION_NAME)
            print(f"ChromaDB 컬렉션 '{CHROMA_COLLECTION_NAME}' 로드/생성 완료. 현재 아이템 수: {CHROMA_COLLECTION.count()}")
        except Exception as e:
            print(f"[치명적 오류] ChromaDB 컬렉션 '{CHROMA_COLLECTION_NAME}' 가져오기/생성 실패: {e}")
            raise SystemExit(f"ChromaDB 컬렉션 가져오기/생성 실패: {e}")
    return CHROMA_COLLECTION

def add_embeddings_to_db(embeddings, metadatas, ids):
    """ChromaDB에 임베딩, 메타데이터, ID를 추가합니다."""
    collection = initialize_chromadb()
    if not collection:
        print("[오류] ChromaDB 컬렉션이 초기화되지 않아 추가 작업을 수행할 수 없습니다.")
        return False
    if not embeddings or not metadatas or not ids:
        print("[오류] DB에 추가할 데이터(임베딩, 메타데이터, ID)가 비어있습니다.")
        return False
    if not (len(embeddings) == len(metadatas) == len(ids)):
        print("[오류] 임베딩, 메타데이터, ID의 개수가 일치하지 않습니다.")
        return False
        
    try:
        collection.add(embeddings=embeddings, metadatas=metadatas, ids=ids)
        return True
    except Exception as e:
        print(f"[오류] ChromaDB에 데이터 추가 중 오류: {e}")
        # traceback.print_exc()
        return False

def query_similar_embeddings(query_embedding, top_n=3):
    """주어진 쿼리 임베딩과 유사한 항목을 ChromaDB에서 검색합니다."""
    collection = initialize_chromadb()
    if not collection:
        print("[오류] ChromaDB 컬렉션이 초기화되지 않아 검색 작업을 수행할 수 없습니다.")
        return None
    if query_embedding is None:
        print("[오류] 검색을 위한 쿼리 임베딩이 없습니다.")
        return None
        
    try:
        results = collection.query(
            query_embeddings=[query_embedding],
            n_results=top_n,
            include=["metadatas", "documents", "distances"] # documents는 저장 시 명시적으로 넣었을 경우
        )
        return results
    except Exception as e:
        print(f"[오류] ChromaDB 검색 중 오류 발생: {e}")
        # traceback.print_exc()
        return None

def get_db_collection_count():
    """DB 컬렉션의 아이템 수를 반환합니다."""
    collection = initialize_chromadb()
    if collection:
        return collection.count()
    return 0

def get_db_entry_by_id(entry_id):
    """ID로 DB 항목을 가져옵니다."""
    collection = initialize_chromadb()
    if collection and entry_id:
        return collection.get(ids=[entry_id])
    return None