// lib/widgets/codemirror_editor.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart' as webview_windows;

class CodeMirrorEditor extends StatefulWidget {
  final String? initialText;
  final Function(String)? onTextChanged;
  final TextEditingController? controller; // ✨ [추가] 컨트롤러 직접 받기

  const CodeMirrorEditor({
    super.key,
    this.initialText,
    this.onTextChanged,
    this.controller, // ✨ [추가]
  });

  @override
  State<CodeMirrorEditor> createState() => CodeMirrorEditorState();
}

class CodeMirrorEditorState extends State<CodeMirrorEditor> {
  final webview_windows.WebviewController _controller =
      webview_windows.WebviewController();
  bool isLoading = true;
  String _currentText = '';
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentText = widget.controller?.text ?? widget.initialText ?? '';
    widget.controller?.addListener(_onControllerChanged);
    print(
      '🚀 CodeMirrorEditor initState - initialText 길이: ${_currentText.length}',
    );
    _initWebView();
  }

  // ✨ [추가] 외부 컨트롤러의 변경을 감지하는 리스너
  void _onControllerChanged() {
    final newText = widget.controller!.text;
    if (_currentText != newText && _isInitialized) {
      setText(newText);
    }
  }

  @override
  void didUpdateWidget(covariant CodeMirrorEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      // 컨트롤러가 바뀌면 에디터의 텍스트도 업데이트
      final newText = widget.controller?.text ?? '';
      if (_currentText != newText) {
        setText(newText);
      }
    }
  }

  Future<void> _initWebView() async {
    try {
      print('🔄 WebView 초기화 시작');
      await _controller.initialize();
      print('✅ WebView 초기화 완료');

      _controller.webMessage.listen((message) {
        print('📨 받은 메시지: $message');
        if (message == 'READY') {
          print('✅ READY 메시지 수신');
          setState(() {
            isLoading = false;
            _isInitialized = true;
          });
          if (_currentText.isNotEmpty) {
            print('📝 초기 텍스트 설정 중...');
            setText(_currentText);
          }
        } else if (message.startsWith('ERROR:')) {
          print('❌ WebView 에러: $message');
          setState(() {
            isLoading = false;
            _errorMessage = message;
          });
        } else if (message != 'SAVE_REQUESTED') {
          _currentText = message;
          widget.onTextChanged?.call(message);
          // ✨ [수정] 외부 컨트롤러에도 변경 사항 전파
          if (widget.controller?.text != message) {
            final currentSelection = widget.controller?.selection;
            widget.controller?.text = message;
            // 커서 위치가 변경되지 않도록 유지
            if (currentSelection != null) {
              try {
                widget.controller?.selection = currentSelection;
              } catch (e) {
                // selection 범위가 벗어나는 경우 오류 방지
                widget.controller?.selection = TextSelection.collapsed(
                  offset: message.length,
                );
              }
            }
          }
        }
      });

      print('🔄 HTML 컨텐츠 로드 시작');
      final htmlContent = _getHtmlContent();
      print('✅ HTML 컨텐츠 생성 완료');

      await _controller.loadStringContent(htmlContent);
      print('✅ WebView에 컨텐츠 로드 완료');

      // 타임아웃 설정
      Future.delayed(const Duration(seconds: 10), () {
        if (isLoading && mounted) {
          print('⚠️ 타임아웃: READY 메시지를 받지 못했습니다');
          setState(() {
            isLoading = false;
            _errorMessage = 'WebView 초기화 시간 초과 - 인터넷 연결을 확인하세요';
          });
        }
      });
    } catch (e) {
      print('❌ WebView 초기화 오류: $e');
      setState(() {
        isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String _getHtmlContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    print('🎨 테마: ${isDark ? "다크" : "라이트"}');

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/theme/material-darker.min.css">
  
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { 
      background: ${isDark ? '#1e1e1e' : '#ffffff'}; 
      overflow: hidden;
      margin: 0;
      padding: 0;
    }
    .CodeMirror {
      height: 100vh;
      font-size: 16px;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
      line-height: 1.6;
    }
    .CodeMirror-scroll { padding: 16px; }
    .CodeMirror-cursor { border-left: 2px solid ${isDark ? '#ffffff' : '#000000'} !important; }
    .CodeMirror-selected { background: ${isDark ? 'rgba(96, 165, 250, 0.3)' : 'rgba(59, 130, 246, 0.2)'} !important; }
    
    /* 옵시디언 스타일 마크다운 */
    .cm-header-1 { 
      font-size: 2em; 
      font-weight: 700; 
      line-height: 1.3;
      color: ${isDark ? '#FFFFFF' : '#1a1a1a'};
    }
    .cm-header-2 { 
      font-size: 1.5em; 
      font-weight: 700; 
      line-height: 1.3;
      color: ${isDark ? '#F0F0F0' : '#2a2a2a'};
    }
    .cm-header-3 { 
      font-size: 1.3em; 
      font-weight: 600; 
      line-height: 1.3;
      color: ${isDark ? '#E8E8E8' : '#3a3a3a'};
    }
    .cm-header-4 { font-size: 1.15em; font-weight: 600; line-height: 1.3; }
    .cm-header-5 { font-size: 1.05em; font-weight: 600; line-height: 1.3; }
    .cm-header-6 { font-size: 1em; font-weight: 600; line-height: 1.3; }
    
    .cm-strong { font-weight: 700; }
    .cm-em { font-style: italic; }
    .cm-strikethrough { 
      text-decoration: line-through;
      color: ${isDark ? '#888888' : '#999999'};
    }
    .cm-link { 
      color: ${isDark ? '#61afef' : '#3498db'}; 
      text-decoration: underline; 
    }
    .cm-url { 
      color: ${isDark ? '#61afef' : '#3498db'}; 
    }
    .cm-comment {
      background: ${isDark ? 'rgba(255,255,255,0.1)' : '#f5f5f5'};
      padding: 2px 4px;
      border-radius: 3px;
      color: ${isDark ? '#e06c75' : '#e74c3c'};
      font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
      font-size: 14px;
    }
    .cm-quote { 
      color: ${isDark ? '#9E9E9E' : '#7f8c8d'}; 
      font-style: italic;
      border-left: 3px solid ${isDark ? '#404040' : '#E0E0E0'};
      padding-left: 10px;
    }
    .cm-variable-2 { color: ${isDark ? '#98c379' : '#27ae60'}; }
    .cm-variable-3 { color: ${isDark ? '#61afef' : '#3498db'}; }
    
    /* 리스트 */
    .cm-keyword { color: ${isDark ? '#c678dd' : '#9b59b6'}; }
    
    /* 태그 */
    .cm-tag { color: ${isDark ? '#c678dd' : '#9b59b6'}; font-weight: 500; }
    
    /* 하이라이트 */
    .cm-formatting-highlight {
      background: ${isDark ? 'rgba(255, 235, 59, 0.25)' : 'rgba(255, 235, 59, 0.4)'};
    }
  </style>
</head>
<body>
  <textarea id="editor"></textarea>

  <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/addon/mode/overlay.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/mode/xml/xml.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/mode/markdown/markdown.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/mode/gfm/gfm.min.js"></script>
  
  <script>
    console.log('🔄 에디터 초기화 시작');
    
    (function() {
      try {
        if (typeof CodeMirror === 'undefined') {
          console.error('❌ CodeMirror가 정의되지 않았습니다!');
          window.chrome.webview.postMessage('ERROR: CodeMirror undefined - 인터넷 연결을 확인하세요');
          return;
        }
        
        console.log('✅ CodeMirror 객체 확인됨');
        console.log('✅ overlayMode 확인:', typeof CodeMirror.overlayMode);
        console.log('📝 사용 모드: GFM (GitHub Flavored Markdown)');
        
        const editor = CodeMirror.fromTextArea(
          document.getElementById('editor'),
          {
            mode: 'gfm',
            lineWrapping: true,
            theme: '${isDark ? 'material-darker' : 'default'}',
            lineNumbers: false,
            autofocus: true,
            placeholder: '메모를 시작하세요...',
            indentUnit: 2,
            tabSize: 2,
            indentWithTabs: false,
            extraKeys: {
              "Enter": "newlineAndIndentContinueMarkdownList"
            }
          }
        );
        
        console.log('✅ CodeMirror 초기화 완료');
        
        let isUpdating = false;
        
        editor.on('change', function() {
          if (isUpdating) return;
          try {
            const value = editor.getValue();
            window.chrome.webview.postMessage(value);
          } catch (e) {
            console.error('❌ 메시지 전송 오류:', e);
          }
        });
        
        window.setText = function(text) {
          try {
            const cursor = editor.getCursor(); // 현재 커서 위치 저장
            isUpdating = true;
            editor.setValue(text);
            isUpdating = false;
            editor.setCursor(cursor); // 커서 위치 복원
            console.log('✅ setText 완료');
          } catch (e) {
            isUpdating = false;
            console.error('❌ setText 오류:', e);
            window.chrome.webview.postMessage('ERROR: ' + e.message);
          }
        };

        window.getText = function() {
          try {
            return editor.getValue();
          } catch (e) {
            console.error('❌ getText 오류:', e);
            return '';
          }
        };
        
        window.insertText = function(text) {
          try {
            editor.replaceSelection(text);
          } catch (e) {
            console.error('❌ insertText 오류:', e);
          }
        };

        // ✨ [추가] 서식 토글 함수
        window.toggleMarkdown = function(prefix, suffix) {
            const selection = editor.getSelection();
            if (selection.startsWith(prefix) && selection.endsWith(suffix)) {
                // 서식 제거
                const unwrapped = selection.substring(prefix.length, selection.length - suffix.length);
                editor.replaceSelection(unwrapped);
            } else {
                // 서식 추가
                editor.replaceSelection(prefix + selection + suffix);
            }
        };

        // ✨ [추가] 들여쓰기/내어쓰기 함수
        window.handleIndent = function(isIndent) {
            if (isIndent) {
                CodeMirror.commands.indentMore(editor);
            } else {
                CodeMirror.commands.indentLess(editor);
            }
        };

        
        setTimeout(function() {
          console.log('📨 READY 메시지 전송 시도');
          try {
            window.chrome.webview.postMessage('READY');
            console.log('✅ READY 메시지 전송 완료');
          } catch (e) {
            console.error('❌ READY 메시지 전송 실패:', e);
          }
        }, 100);
        
      } catch (e) {
        console.error('❌ 에디터 초기화 오류:', e);
        try {
          window.chrome.webview.postMessage('ERROR: ' + e.message);
        } catch (err) {
          console.error('❌ 에러 메시지 전송 실패:', err);
        }
      }
    })();
  </script>
</body>
</html>
    ''';
  }

  Future<void> setText(String text) async {
    _currentText = text;
    if (_isInitialized && !isLoading) {
      final escaped = text
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "\\'")
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '');
      try {
        await _controller.executeScript("window.setText('$escaped')");
        print('✅ setText 실행 완료');
      } catch (e) {
        print('❌ setText 오류: $e');
      }
    } else {
      print(
        '⚠️ setText 스킵 - isInitialized: $_isInitialized, isLoading: $isLoading',
      );
    }
  }

  Future<String> getText() async {
    if (isLoading || !_isInitialized) {
      print('⚠️ getText - 아직 초기화되지 않음. 캐시된 텍스트 반환');
      return _currentText;
    }
    try {
      final result = await _controller.executeScript('window.getText()');
      print('✅ getText 완료');
      return result?.toString().replaceAll('"', '') ?? _currentText;
    } catch (e) {
      print('❌ getText 오류: $e');
      return _currentText;
    }
  }

  Future<void> insertText(String text) async {
    if (!_isInitialized) {
      print('⚠️ insertText - 아직 초기화되지 않음');
      return;
    }

    final escaped = text.replaceAll("'", "\\'");
    try {
      await _controller.executeScript("window.insertText('$escaped')");
      print('✅ insertText 완료');
    } catch (e) {
      print('❌ insertText 오류: $e');
    }
  }

  // --- ✨ [추가] 단축키를 위한 공개 메서드들 ---
  Future<void> toggleBold() async {
    if (!_isInitialized) return;
    try {
      await _controller.executeScript("window.toggleMarkdown('**', '**')");
    } catch (e) {
      print('❌ toggleBold 오류: $e');
    }
  }

  Future<void> toggleItalic() async {
    if (!_isInitialized) return;
    try {
      await _controller.executeScript("window.toggleMarkdown('*', '*')");
    } catch (e) {
      print('❌ toggleItalic 오류: $e');
    }
  }

  Future<void> indent() async {
    if (!_isInitialized) return;
    try {
      await _controller.executeScript("window.handleIndent(true)");
    } catch (e) {
      print('❌ indent 오류: $e');
    }
  }

  Future<void> outdent() async {
    if (!_isInitialized) return;
    try {
      await _controller.executeScript("window.handleIndent(false)");
    } catch (e) {
      print('❌ outdent 오류: $e');
    }
  }
  // ---

  @override
  void dispose() {
    print('🗑️ CodeMirrorEditor dispose');
    widget.controller?.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            constraints.maxHeight == double.infinity
                ? MediaQuery.of(context).size.height - 100
                : constraints.hasBoundedHeight
                ? constraints.maxHeight
                : 600.0;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              if (_isInitialized)
                webview_windows.Webview(_controller)
              else
                Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(
                    child:
                        _errorMessage != null
                            ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.red,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '에디터 로드 실패',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    _errorMessage!,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            )
                            : null,
                  ),
                ),
              if (isLoading && _errorMessage == null)
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('에디터 로드 중...'),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
