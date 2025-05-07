# prompts.py
from utils.translator import translate_text # 동적 프롬프트 생성 시 번역에 필요

task_prompts = {
    "classify": """Analyze the following text and classify its primary content type using one of the following labels:
- meeting_notes (Contains discussion points, decisions, action items)
- idea_brainstorming (Lists ideas, free-form thoughts)
- technical_explanation (Describes a process, technology, or method)
- personal_reflection (Personal thoughts, diary-like content)
- todo_list (A list of tasks to be done)
- general_information (Factual information, news summary, etc.)
- other (If none of the above fit well)
Please respond with ONLY the most appropriate label in lowercase English (e.g., meeting_notes).

[TEXT]""",
    "summarize": "Please summarize the following text in three concise sentences, capturing the main points:\n[TEXT]",
    "memo": "Based on the following content, create bullet points highlighting the key ideas and decisions:\n[TEXT]",
    "keyword": """Analyze the following text. Identify the 5 most important keywords relevant to the main topic.
For each keyword, estimate its importance score as a decimal number between 0.0 and 1.0 (e.g., 0.75, 0.9).
Output Format Rules:
1. You MUST list exactly 5 keyword-score pairs.
2. Each pair MUST be on a new line.
3. The format for each line MUST be exactly: `keyword: score` (e.g., `artificial intelligence: 0.95`).
4. The score MUST be a decimal number between 0.0 and 1.0, inclusive.
5. Do NOT include any other text, explanations, introductions, or summaries. Output ONLY the 5 keyword-score pairs in the specified format.
[TEXT]""",
    "comparison": """Below are two lists of keywords, each extracted from a different text (Text 1 and Text 2).
Evaluate the thematic similarity between Text 1 and Text 2 based ONLY on these keywords.
Provide a single similarity score between 0.0 (no similarity) and 1.0 (very high similarity).
Output ONLY the numerical score, rounded to two decimal places (e.g., 0.75).
Keywords from Text 1:
[KEYWORDS1]
Keywords from Text 2:
[KEYWORDS2]""",
}

def create_adaptive_prompt(user_input_ko, task_type, content_type):
    """내용 유형에 따라 작업 프롬프트를 동적으로 조정하고 영어로 번역합니다."""
    if task_type not in task_prompts:
        # 기본 프롬프트가 없는 경우, 일반적인 지시문 또는 오류 처리
        print(f"[Warning] '{task_type}'에 대한 기본 프롬프트 템플릿이 없습니다.")
        # 간단한 기본 요약 프롬프트를 사용하거나, 예외를 발생시킬 수 있습니다.
        # 여기서는 입력을 그대로 사용하는 일반 프롬프트를 반환하도록 합니다 (LLM이 알아서 처리하도록).
        # 또는, 특정 기본 프롬프트를 사용할 수 있습니다.
        # 예: base_prompt_template = "Process the following text: [TEXT]"
        # 더 나은 방법은 task_prompts에 모든 task_type에 대한 기본값을 두는 것입니다.
        base_prompt_template = f"Based on the content type '{content_type}', perform the task '{task_type}' on the following text:\n[TEXT]"
    else:
        base_prompt_template = task_prompts[task_type]
        
    adapted_prompt_template = base_prompt_template # 기본값 설정

    # 내용 유형에 따른 프롬프트 조정 (영어 템플릿 기준)
    if task_type == "memo":
        if content_type == "meeting_notes":
            adapted_prompt_template = "Based on the following meeting notes, create clear bullet points for **key discussion points, decisions made, and action items (including responsible persons if mentioned)**:\n[TEXT]"
        elif content_type == "idea_brainstorming":
            adapted_prompt_template = "From the following brainstorming content, organize the **core ideas and related key points** into bullet points:\n[TEXT]"
        # ... (기타 content_type에 대한 조건 추가 가능) ...
        else: # 다른 유형은 기본 메모 프롬프트 사용
            adapted_prompt_template = task_prompts.get("memo", base_prompt_template) 

    elif task_type == "summarize":
        if content_type == "technical_explanation":
            adapted_prompt_template = "Summarize the following technical text in three sentences, focusing on the **core purpose, main methodology/process (if any), and significant results or conclusions**:\n[TEXT]"
        # ... (기타 content_type에 대한 조건 추가 가능) ...
        else: # 다른 유형은 기본 요약 프롬프트 사용
            adapted_prompt_template = task_prompts.get("summarize", base_prompt_template)

    # 사용자 입력(ko)을 영어로 번역 ('auto' 사용 가능)
    user_input_en = translate_text(user_input_ko, 'auto', 'en')
    if user_input_en.startswith("Error"):
        # 번역 실패 시, 원본 한국어 입력을 사용하고 LLM이 다국어 처리가 가능하다고 가정하거나,
        # 오류를 발생시켜 상위에서 처리하도록 할 수 있습니다.
        # 여기서는 예외를 발생시킵니다.
        raise Exception(f"적응형 프롬프트 생성 시 사용자 입력 번역 실패: {user_input_en}")

    # 영어 템플릿에 번역된 영어 사용자 입력을 삽입
    final_prompt_en = adapted_prompt_template.replace("[TEXT]", user_input_en)
    return final_prompt_en