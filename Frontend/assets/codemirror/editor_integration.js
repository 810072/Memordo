// assets/codemirror/editor_integration.js
// CodeMirror와 Flutter 간의 통신을 담당하는 JavaScript

(function() {
  'use strict';

  // 상태 변수
  let isSuggestionBoxVisible = false;
  let highlightedIndex = -1;
  let suggestionCount = 0;
  let isUpdatingFromJs = false;
  let editor = null;

  // PostMessage API (Windows vs 크로스플랫폼)
  // 이 부분은 HTML 빌드 시 교체됩니다
  const postMessage = typeof window.chrome !== 'undefined' && 
                      typeof window.chrome.webview !== 'undefined'
    ? window.chrome.webview.postMessage
    : window.FlutterChannel.postMessage;

  // 헬퍼 함수: JSON 메시지 전송
  function sendMessage(data) {
    try {
      postMessage(JSON.stringify(data));
    } catch (e) {
      console.error('메시지 전송 실패:', e);
    }
  }

  // 헬퍼 함수: 텍스트 메시지 전송
  function sendTextMessage(message) {
    try {
      postMessage(message);
    } catch (e) {
      console.error('텍스트 메시지 전송 실패:', e);
    }
  }

  // Flutter로 에디터 상태 전송
  function sendStateToFlutter() {
    if (isUpdatingFromJs || !editor) return;
    
    try {
      const text = editor.getValue();
      const offset = editor.indexFromPos(editor.getCursor());
      sendMessage({
        type: 'update',
        text: text,
        offset: offset
      });
    } catch (e) {
      console.error('상태 전송 실패:', e);
    }
  }

  // ✨ [추가] 볼드 토글 함수
  function toggleBold(cm) {
    const selection = cm.getSelection();
    const cursor = cm.getCursor();
    
    if (selection) {
      // 선택 영역이 있으면
      if (selection.startsWith('**') && selection.endsWith('**')) {
        // 이미 볼드면 제거
        cm.replaceSelection(selection.slice(2, -2));
      } else {
        // 볼드 추가
        cm.replaceSelection('**' + selection + '**');
      }
    } else {
      // 선택 영역이 없으면 커서 위치에 템플릿 삽입
      cm.replaceSelection('****');
      cm.setCursor({ line: cursor.line, ch: cursor.ch + 2 });
    }
    cm.focus();
  }

  // ✨ [추가] 이탤릭 토글 함수
  function toggleItalic(cm) {
    const selection = cm.getSelection();
    const cursor = cm.getCursor();
    
    if (selection) {
      if (selection.startsWith('*') && selection.endsWith('*') && 
          !selection.startsWith('**')) {
        // 이미 이탤릭이면 제거
        cm.replaceSelection(selection.slice(1, -1));
      } else {
        // 이탤릭 추가
        cm.replaceSelection('*' + selection + '*');
      }
    } else {
      cm.replaceSelection('**');
      cm.setCursor({ line: cursor.line, ch: cursor.ch + 1 });
    }
    cm.focus();
  }

  // 위키링크 패턴 감지 및 제안 박스 표시
  function handleWikiLinkSuggestions(cm) {
    const cursor = cm.getCursor();
    const lineText = cm.getLine(cursor.line);
    const textBeforeCursor = lineText.substring(0, cursor.ch);
    
    // [[...]] 패턴 매칭 (닫는 브래킷이 없는 경우)
    const match = textBeforeCursor.match(/\[\[([^\]\[\]]*)$/);
    
    if (match) {
      const query = match[1];
      const textAfterCursor = lineText.substring(cursor.ch);
      
      // 닫는 브래킷이 없으면 제안 박스 표시
      if (!textAfterCursor.includes(']]')) {
        // 1. [[의 시작 위치 계산
        const startOfLink = textBeforeCursor.lastIndexOf('[[');
        const startPos = { line: cursor.line, ch: startOfLink };

        // 2. 페이지 좌표로 변환 (스크롤 자동 반영)
        const coords = cm.charCoords(startPos, 'page');

        // 3. CodeMirror 컨테이너의 화면 상 위치 얻기
        const wrapper = cm.getWrapperElement();
        const wrapperRect = wrapper.getBoundingClientRect();

        // 4. 컨테이너 기준 상대 좌표로 변환
        const relativeX = coords.left - wrapperRect.left;
        const relativeY = coords.bottom - wrapperRect.top;

        // 5. 스크롤 정보도 함께 전달
        const scrollInfo = cm.getScrollInfo();

        sendMessage({
          type: 'show-wikilink',
          query: query,
          x: relativeX,
          y: relativeY,
          // 추가 정보
          scrollTop: scrollInfo.top,
          scrollLeft: scrollInfo.left,
          wrapperTop: wrapperRect.top,
          wrapperLeft: wrapperRect.left
        });
        
        isSuggestionBoxVisible = true;
        return;
      }
    }
    
    // 패턴이 없으면 제안 박스 숨김
    if (isSuggestionBoxVisible) {
      sendMessage({ type: 'hide-wikilink' });
      isSuggestionBoxVisible = false;
      highlightedIndex = -1;
    }
  }

  // ✨ [수정] 개선된 링크 클릭 핸들러
  function handleLinkClick(event) {
    if (!event.ctrlKey && !event.metaKey) return;
    
    const target = event.target;
    const cm = editor;
    
    // 1. 일반 URL 처리 (.cm-url 클래스)
    if (target.classList.contains('cm-url')) {
      event.preventDefault();
      const url = target.innerText.trim();
      if (url) {
        sendMessage({ type: 'open-url', url: url });
      }
      return;
    }
    
    // 2. 링크 처리 (.cm-link 클래스)
    if (target.classList.contains('cm-link')) {
      event.preventDefault();
      
      // 클릭 위치의 좌표를 CodeMirror 좌표로 변환
      const rect = cm.getWrapperElement().getBoundingClientRect();
      const pos = cm.coordsChar({
        left: event.clientX - rect.left,
        top: event.clientY - rect.top
      });
      
      const line = cm.getLine(pos.line);
      if (!line) return;
      
      // 위키링크 패턴 찾기 [[파일명]]
      const wikiLinkRegex = /\[\[([^\]]+)\]\]/g;
      let wikiMatch;
      
      while ((wikiMatch = wikiLinkRegex.exec(line)) !== null) {
        const startIndex = wikiMatch.index;
        const endIndex = startIndex + wikiMatch[0].length;
        
        // 클릭 위치가 이 위키링크 안에 있는지 확인
        if (pos.ch >= startIndex && pos.ch <= endIndex) {
          const fileName = wikiMatch[1]; // [[파일명]] → 파일명
          sendMessage({ type: 'open-wikilink', fileName: fileName });
          return;
        }
      }
      
      // 마크다운 링크 패턴 찾기 [텍스트](URL)
      const markdownLinkRegex = /\[([^\]]+)\]\(([^)]+)\)/g;
      let mdMatch;
      
      while ((mdMatch = markdownLinkRegex.exec(line)) !== null) {
        const startIndex = mdMatch.index;
        const endIndex = startIndex + mdMatch[0].length;
        
        // 클릭 위치가 이 마크다운 링크 안에 있는지 확인
        if (pos.ch >= startIndex && pos.ch <= endIndex) {
          const url = mdMatch[2]; // [텍스트](URL) → URL
          sendMessage({ type: 'open-url', url: url });
          return;
        }
      }
    }
  }

  // CodeMirror 키 바인딩
  const extraKeys = {
    "Enter": function(cm) {
      if (isSuggestionBoxVisible && highlightedIndex !== -1) {
        sendMessage({ type: 'select-suggestion' });
        return;
      }
      return CodeMirror.Pass;
    },
    
    "Esc": function(cm) {
      if (isSuggestionBoxVisible) {
        sendMessage({ type: 'hide-wikilink' });
        return;
      }
      return CodeMirror.Pass;
    },
    
    "ArrowDown": function(cm) {
      if (isSuggestionBoxVisible && suggestionCount > 0) {
        highlightedIndex = (highlightedIndex + 1) % suggestionCount;
        sendMessage({ 
          type: 'highlight-suggestion', 
          index: highlightedIndex 
        });
        return;
      }
      return CodeMirror.Pass;
    },
    
    "ArrowUp": function(cm) {
      if (isSuggestionBoxVisible && suggestionCount > 0) {
        highlightedIndex = (highlightedIndex - 1 + suggestionCount) % suggestionCount;
        sendMessage({ 
          type: 'highlight-suggestion', 
          index: highlightedIndex 
        });
        return;
      }
      return CodeMirror.Pass;
    },
    
    // ✨ [수정] 직접 구현한 함수 사용
    "Ctrl-B": toggleBold,
    "Ctrl-I": toggleItalic,
    "Tab": "indentMore",
    "Shift-Tab": "indentLess",
    "Ctrl-S": (cm) => sendTextMessage('SAVE_REQUESTED'),
  };

  // CodeMirror 초기화
  function initializeEditor() {
    try {
      const textarea = document.getElementById('editor');
      if (!textarea) {
        throw new Error('에디터 textarea를 찾을 수 없습니다.');
      }

      editor = CodeMirror.fromTextArea(textarea, {
        mode: 'gfm',
        lineWrapping: true,
        theme: 'default',
        autofocus: true,
        placeholder: '메모를 시작하세요...',
        styleActiveLine: { nonEmpty: true },
        indentUnit: 2,
        tabSize: 2,
        extraKeys: extraKeys
      });

      // 이벤트 리스너 등록
      editor.on('cursorActivity', (cm) => {
        sendStateToFlutter();
        handleWikiLinkSuggestions(cm);
      });

      editor.on('change', () => {
        sendStateToFlutter();
      });

      // 링크 클릭 이벤트
      editor.getWrapperElement().addEventListener('mousedown', handleLinkClick);

      // 초기 상태: 문법 숨김
      editor.getWrapperElement().classList.add('hide-formatting');

      // Flutter에 준비 완료 알림
      setTimeout(() => {
        sendTextMessage('READY');
      }, 200);

    } catch (e) {
      sendTextMessage('ERROR: ' + e.message);
      throw e;
    }
  }

  // Flutter에서 호출할 수 있는 전역 함수들
  window.setText = function(text) {
    if (!editor) {
      console.error('에디터가 초기화되지 않았습니다.');
      return;
    }
    
    try {
      const cursor = editor.getCursor();
      isUpdatingFromJs = true;
      editor.setValue(text);
      isUpdatingFromJs = false;
      editor.setCursor(cursor);
    } catch (e) {
      console.error('setText 오류:', e);
      isUpdatingFromJs = false;
    }
  };

  window.getText = function() {
    if (!editor) {
      console.error('에디터가 초기화되지 않았습니다.');
      return '';
    }
    
    try {
      return editor.getValue();
    } catch (e) {
      console.error('getText 오류:', e);
      return '';
    }
  };

  window.toggleFormatting = function(show) {
    if (!editor) {
      console.error('에디터가 초기화되지 않았습니다.');
      return;
    }
    
    try {
      const wrapper = editor.getWrapperElement();
      if (show) {
        wrapper.classList.remove('hide-formatting');
      } else {
        wrapper.classList.add('hide-formatting');
      }
    } catch (e) {
      console.error('toggleFormatting 오류:', e);
    }
  };

  window.updateSuggestionCount = function(count) {
    try {
      suggestionCount = count;
      highlightedIndex = count > 0 ? 0 : -1;
      
      if (isSuggestionBoxVisible) {
        sendMessage({
          type: 'highlight-suggestion',
          index: highlightedIndex
        });
      }
    } catch (e) {
      console.error('updateSuggestionCount 오류:', e);
    }
  };

  window.insertWikiLink = function(fileName) {
    if (!editor) {
      console.error('에디터가 초기화되지 않았습니다.');
      return;
    }
    
    try {
      isSuggestionBoxVisible = false;
      highlightedIndex = -1;
      
      const cursor = editor.getCursor();
      const lineText = editor.getLine(cursor.line);
      const textBeforeCursor = lineText.substring(0, cursor.ch);
      const startMatch = textBeforeCursor.lastIndexOf('[[');
      
      if (startMatch !== -1) {
        const wikiLink = '[[' + fileName + ']]';
        editor.replaceRange(
          wikiLink,
          { line: cursor.line, ch: startMatch },
          cursor
        );
        editor.focus();
      }
    } catch (e) {
      console.error('insertWikiLink 오류:', e);
    }
  };

  // 에디터 상태 확인 (디버깅용)
  window.getEditorState = function() {
    return {
      initialized: !!editor,
      suggestionBoxVisible: isSuggestionBoxVisible,
      highlightedIndex: highlightedIndex,
      suggestionCount: suggestionCount
    };
  };

  // DOM 로드 완료 후 초기화
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeEditor);
  } else {
    initializeEditor();
  }

})();