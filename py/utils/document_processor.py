# utils/document_processor.py
from pathlib import Path
from config import CHUNK_SENTS_PER_CHUNK

def get_document_paths(doc_dir):
    """지정된 디렉토리에서 모든 .md 파일 경로 리스트를 반환"""
    doc_path = Path(doc_dir)
    if not doc_path.is_dir():
        print(f"[오류] 문서 디렉토리 '{doc_dir}'를 찾을 수 없거나 디렉토리가 아닙니다.")
        return []
    # rglob: 하위 디렉토리 포함 검색
    return list(doc_path.rglob('*.md'))

def read_document_content(filepath):
    """파일 경로를 받아 내용을 읽어 반환"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        print(f"[오류] 파일을 찾을 수 없습니다: {filepath}")
        return None
    except Exception as e:
        print(f"[오류] 파일 읽기 오류 ({filepath}): {e}")
        return None

def chunk_text_by_sentences(text, sentences_per_chunk=CHUNK_SENTS_PER_CHUNK):
    """텍스트를 문장 단위로 청킹하는 간단한 함수"""
    if not text or not isinstance(text, str) or not text.strip():
        return []
    
    delimiters = ".!?\n" # 문장 구분자
    temp_sentences = []
    current_sentence_buffer = ""
    for char in text:
        current_sentence_buffer += char
        if char in delimiters:
            if current_sentence_buffer.strip():
                temp_sentences.append(current_sentence_buffer.strip())
            current_sentence_buffer = ""
    if current_sentence_buffer.strip(): # 마지막 문장 처리
        temp_sentences.append(current_sentence_buffer.strip())

    if not temp_sentences:
        return [text.strip()] if text.strip() else []

    chunks = []
    current_chunk_sentences = []
    for i, sentence in enumerate(temp_sentences):
        current_chunk_sentences.append(sentence)
        if (i + 1) % sentences_per_chunk == 0 or (i + 1) == len(temp_sentences):
            chunks.append(" ".join(current_chunk_sentences))
            current_chunk_sentences = []
    return chunks