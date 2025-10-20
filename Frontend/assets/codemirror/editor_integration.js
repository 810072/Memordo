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
  let currentActiveLine = -1; // ✨ 현재 활성 라인 추적

  // PostMessage API (Windows vs 크로스플랫폼)
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

  // ✨ [수정] 활성 라인 스타일 업데이트
  function updateActiveLineFormatting() {
    if (!editor) return;
    
    const cursor = editor.getCursor();
    const newActiveLine = cursor.line;
    
    // 라인이 변경되었을 때만 업데이트
    if (newActiveLine !== currentActiveLine) {
      currentActiveLine = newActiveLine;
      
      // 모든 라인의 active 클래스 제거
      const allLines = document.querySelectorAll('.CodeMirror-line');
      allLines.forEach(line => {
        line.classList.remove('active-line-formatting');
      });
      
      // 현재 라인에 클래스 추가
      const lineElement = editor.getLineHandle(newActiveLine);
      if (lineElement && lineElement.text !== undefined) {
        // CodeMirror의 실제 DOM 라인 찾기
        const wrapper = editor.getWrapperElement();
        const lines = wrapper.querySelectorAll('.CodeMirror-line');
        if (lines[newActiveLine]) {
          lines[newActiveLine].classList.add('active-line-formatting');
        }
      }
    }
  }

  // ✨ [수정] 마크다운 문법 기호를 감지하는 커스텀 Overlay
  CodeMirror.defineMode("markdown-formatting", function(config, parserConfig) {
    const markdownConfig = CodeMirror.getMode(config, "gfm");
    
    const overlay = {
      token: function(stream, state) {
        // 볼드: **text**
        if (stream.match(/\*\*/)) {
          return "formatting formatting-strong";
        }
        
        // 이탤릭: *text* 또는 _text_ (볼드가 아닐 때만)
        if (stream.match(/(?<!\*)\*(?!\*)/)) {
          return "formatting formatting-em";
        }
        if (stream.match(/_/)) {
          return "formatting formatting-em";
        }
        
        // 헤더: # ## ###
        if (stream.sol() && stream.match(/^#{1,6}\s/)) {
          return "formatting formatting-header";
        }
        
        // ✨ [수정] 위키링크는 formatting 제외 (항상 보임)
        if (stream.match(/\[\[/)) {
          return "wikilink-bracket";
        }
        if (stream.match(/\]\]/)) {
          return "wikilink-bracket";
        }
        
        // ✨ [수정] 마크다운 링크의 URL 부분만 숨김
        // [텍스트](URL) 패턴 감지
        if (stream.match(/\[/)) {
          return "formatting formatting-link";
        }
        // ]( 부분과 URL, ) 모두 숨김
        if (stream.match(/\]\([^)]*\)/)) {
          return "formatting formatting-link-url";
        }
        
        // 코드: `code`
        if (stream.match(/`/)) {
          return "formatting formatting-code";
        }
        
        // 리스트: - * +
        if (stream.sol() && stream.match(/^[\-\*\+]\s/)) {
          return "formatting formatting-list";
        }
        
        // 인용: >
        if (stream.sol() && stream.match(/^>\s?/)) {
          return "formatting formatting-quote";
        }
        
        // 취소선: ~~text~~
        if (stream.match(/~~/)) {
          return "formatting formatting-strikethrough";
        }
        
        stream.next();
        return null;
      }
    };
    
    return CodeMirror.overlayMode(markdownConfig, overlay);
  });

  // 볼드 토글 함수
  function toggleBold(cm) {
    const selection = cm.getSelection();
    const cursor = cm.getCursor();
    
    if (selection) {
      if (selection.startsWith('**') && selection.endsWith('**')) {
        cm.replaceSelection(selection.slice(2, -2));
      } else {
        cm.replaceSelection('**' + selection + '**');
      }
    } else {
      cm.replaceSelection('****');
      cm.setCursor({ line: cursor.line, ch: cursor.ch + 2 });
    }
    cm.focus();
  }

  // 이탤릭 토글 함수
  function toggleItalic(cm) {
    const selection = cm.getSelection();
    const cursor = cm.getCursor();
    
    if (selection) {
      if (selection.startsWith('*') && selection.endsWith('*') && 
          !selection.startsWith('**')) {
        cm.replaceSelection(selection.slice(1, -1));
      } else {
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
    
    const match = textBeforeCursor.match(/\[\[([^\]\[\]]*)$/);
    
    if (match) {
      const query = match[1];
      const textAfterCursor = lineText.substring(cursor.ch);
      
      if (!textAfterCursor.includes(']]')) {
        const startOfLink = textBeforeCursor.lastIndexOf('[[');
        const startPos = { line: cursor.line, ch: startOfLink };
        const coords = cm.charCoords(startPos, 'page');
        const wrapper = cm.getWrapperElement();
        const wrapperRect = wrapper.getBoundingClientRect();
        const relativeX = coords.left - wrapperRect.left;
        const relativeY = coords.bottom - wrapperRect.top;
        const scrollInfo = cm.getScrollInfo();

        sendMessage({
          type: 'show-wikilink',
          query: query,
          x: relativeX,
          y: relativeY,
          scrollTop: scrollInfo.top,
          scrollLeft: scrollInfo.left,
          wrapperTop: wrapperRect.top,
          wrapperLeft: wrapperRect.left
        });
        
        isSuggestionBoxVisible = true;
        return;
      }
    }
    
    if (isSuggestionBoxVisible) {
      sendMessage({ type: 'hide-wikilink' });
      isSuggestionBoxVisible = false;
      highlightedIndex = -1;
    }
  }

  // 링크 클릭 핸들러
  function handleLinkClick(event) {
    if (!event.ctrlKey && !event.metaKey) return;
    
    const target = event.target;
    const cm = editor;
    
    if (target.classList.contains('cm-url')) {
      event.preventDefault();
      const url = target.innerText.trim();
      if (url) {
        sendMessage({ type: 'open-url', url: url });
      }
      return;
    }
    
    if (target.classList.contains('cm-link')) {
      event.preventDefault();
      
      const rect = cm.getWrapperElement().getBoundingClientRect();
      const pos = cm.coordsChar({
        left: event.clientX - rect.left,
        top: event.clientY - rect.top
      });
      
      const line = cm.getLine(pos.line);
      if (!line) return;
      
      const wikiLinkRegex = /\[\[([^\]]+)\]\]/g;
      let wikiMatch;
      
      while ((wikiMatch = wikiLinkRegex.exec(line)) !== null) {
        const startIndex = wikiMatch.index;
        const endIndex = startIndex + wikiMatch[0].length;
        
        if (pos.ch >= startIndex && pos.ch <= endIndex) {
          const fileName = wikiMatch[1];
          sendMessage({ type: 'open-wikilink', fileName: fileName });
          return;
        }
      }
      
      const markdownLinkRegex = /\[([^\]]+)\]\(([^)]+)\)/g;
      let mdMatch;
      
      while ((mdMatch = markdownLinkRegex.exec(line)) !== null) {
        const startIndex = mdMatch.index;
        const endIndex = startIndex + mdMatch[0].length;
        
        if (pos.ch >= startIndex && pos.ch <= endIndex) {
          const url = mdMatch[2];
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
        mode: 'markdown-formatting',
        lineWrapping: true,
        theme: 'default',
        autofocus: true,
        placeholder: '메모를 시작하세요...',
        styleActiveLine: false, // ✨ 비활성화 (직접 관리)
        indentUnit: 2,
        tabSize: 2,
        extraKeys: extraKeys
      });

      // ✨ 이벤트 리스너 등록
      editor.on('cursorActivity', (cm) => {
        updateActiveLineFormatting(); // 활성 라인 업데이트
        sendStateToFlutter();
        handleWikiLinkSuggestions(cm);
      });

      editor.on('change', () => {
        sendStateToFlutter();
        // 변경 후에도 활성 라인 업데이트
        setTimeout(() => updateActiveLineFormatting(), 10);
      });

      // 링크 클릭 이벤트
      editor.getWrapperElement().addEventListener('mousedown', handleLinkClick);

      // Flutter에 준비 완료 알림
      setTimeout(() => {
        sendTextMessage('READY');
        console.log('✅ 에디터 초기화 완료 - 커스텀 formatting 모드');
        
        // 초기 활성 라인 설정
        updateActiveLineFormatting();
        
        // 디버깅: formatting 요소 확인
        setTimeout(() => {
          const formattings = document.querySelectorAll('.cm-formatting');
          console.log('📊 cm-formatting 요소 수:', formattings.length);
        }, 500);
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
      updateActiveLineFormatting(); // ✨ 텍스트 설정 후 업데이트
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
      
      console.log('toggleFormatting 호출:', show ? '문법 표시' : '문법 숨김');
      
      if (show) {
        wrapper.classList.remove('hide-formatting');
        console.log('✅ 문법 표시 모드');
      } else {
        wrapper.classList.add('hide-formatting');
        console.log('✅ 문법 숨김 모드 (현재 라인만 표시)');
      }
      
      // 디버깅
      setTimeout(() => {
        const formattings = wrapper.querySelectorAll('.cm-formatting');
        console.log('📊 formatting 요소 수:', formattings.length);
        if (formattings.length > 0) {
          const computed = window.getComputedStyle(formattings[0]);
          console.log('  - font-size:', computed.fontSize);
          console.log('  - opacity:', computed.opacity);
        }
      }, 100);
      
      editor.refresh();
      updateActiveLineFormatting(); // ✨ 토글 후 업데이트
      
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
      suggestionCount: suggestionCount,
      currentActiveLine: currentActiveLine
    };
  };

  // DOM 로드 완료 후 초기화
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeEditor);
  } else {
    initializeEditor();
  }

})();