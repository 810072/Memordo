# utils/embedder.py
from sentence_transformers import SentenceTransformer
from config import SBERT_MODEL_NAME
import traceback

SBERT_MODEL = None # 전역 변수로 모델 관리

def get_sbert_model():
    global SBERT_MODEL
    if SBERT_MODEL is None:
        try:
            SBERT_MODEL = SentenceTransformer(SBERT_MODEL_NAME)
            print(f"SentenceTransformer 모델 '{SBERT_MODEL_NAME}' 로드 완료.")
        except Exception as e:
            print(f"[치명적 오류] SentenceTransformer 모델 '{SBERT_MODEL_NAME}' 로드 실패: {e}")
            raise SystemExit(f"SBERT 모델 로드 실패: {e}") # 모델 로드 실패는 심각한 문제
    return SBERT_MODEL

def get_embedding_for_text_en(text_en):
    """영문 텍스트에 대한 SentenceTransformer 임베딩 벡터를 반환."""
    if not text_en or not isinstance(text_en, str) or not text_en.strip():
        return None
    try:
        sbert_model = get_sbert_model() # 모델 로더 호출
        embedding = sbert_model.encode(text_en, convert_to_tensor=False) # numpy array
        return embedding.tolist() # ChromaDB 저장을 위해 리스트로 변환
    except Exception as e:
        print(f"[오류] SentenceTransformer 임베딩 생성 중 오류 ('{text_en[:50]}...'): {e}")
        # traceback.print_exc() # 상세 디버깅 필요 시
        return None