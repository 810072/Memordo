import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as webview_windows;

class CodeMirrorEditor extends StatefulWidget {
  final String? initialText;
  final Function(String)? onTextChanged;

  const CodeMirrorEditor({super.key, this.initialText, this.onTextChanged});

  @override
  State<CodeMirrorEditor> createState() => CodeMirrorEditorState();
}

class CodeMirrorEditorState extends State<CodeMirrorEditor> {
  final webview_windows.WebviewController _controller =
      webview_windows.WebviewController();
  bool isLoading = true;
  String _currentText = '';
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _currentText = widget.initialText ?? '';
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      await _controller.initialize();

      // JavaScript 채널 설정
      _controller.webMessage.listen((message) {
        if (message == 'READY') {
          setState(() {
            isLoading = false;
            _isInitialized = true;
          });
          if (_currentText.isNotEmpty) {
            setText(_currentText);
          }
        } else if (message != 'SAVE_REQUESTED') {
          _currentText = message;
          widget.onTextChanged?.call(message);
        }
      });

      // HTML 로드
      await _controller.loadStringContent(_getHtml());
    } catch (e) {
      print('WebView 초기화 오류: $e');
      setState(() => isLoading = false);
    }
  }

  String _getHtml() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  
  <!-- CodeMirror CSS -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/theme/material-darker.min.css">
  
  <!-- CodeMirror JS -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/mode/markdown/markdown.min.js"></script>
  
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      background: ${isDark ? '#1e1e1e' : '#ffffff'};
      overflow: hidden;
    }
    
    .CodeMirror {
      height: 100vh;
      font-size: 16px;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
      line-height: 1.6;
    }
    
    .CodeMirror-scroll {
      padding: 16px;
    }
    
    /* 커서 스타일 */
    .CodeMirror-cursor {
      border-left: 2px solid ${isDark ? '#ffffff' : '#000000'};
    }
    
    /* 선택 영역 */
    .CodeMirror-selected {
      background: ${isDark ? 'rgba(96, 165, 250, 0.3)' : 'rgba(59, 130, 246, 0.2)'} !important;
    }
    
    /* 헤더 스타일 */
    .cm-header-1 {
      font-size: 2em;
      font-weight: bold;
      line-height: 1.4;
    }
    
    .cm-header-2 {
      font-size: 1.75em;
      font-weight: bold;
      line-height: 1.4;
    }
    
    .cm-header-3 {
      font-size: 1.5em;
      font-weight: 600;
      line-height: 1.4;
    }
    
    /* 볼드, 이탤릭 */
    .cm-strong {
      font-weight: bold;
    }
    
    .cm-em {
      font-style: italic;
    }
    
    /* 링크 */
    .cm-link {
      color: ${isDark ? '#61afef' : '#3498db'};
      text-decoration: underline;
    }
    
    /* 인라인 코드 */
    .cm-comment {
      background: ${isDark ? 'rgba(255,255,255,0.1)' : '#f5f5f5'};
      padding: 2px 4px;
      border-radius: 3px;
      color: ${isDark ? '#e06c75' : '#e74c3c'};
    }
  </style>
</head>
<body>
  <textarea id="editor"></textarea>
  
  <script>
    const editor = CodeMirror.fromTextArea(
      document.getElementById('editor'),
      {
        mode: 'markdown',
        lineWrapping: true,
        theme: '${isDark ? 'material-darker' : 'default'}',
        lineNumbers: false,
        autofocus: true,
        placeholder: '메모를 시작하세요...'
      }
    );
    
    // 텍스트 변경 이벤트
    editor.on('change', function() {
      window.chrome.webview.postMessage(editor.getValue());
    });
    
    // Flutter에서 호출할 함수들
    window.setText = function(text) {
      editor.setValue(text);
    };
    
    window.getText = function() {
      return editor.getValue();
    };
    
    window.insertText = function(text) {
      editor.replaceSelection(text);
    };
    
    // 단축키
    editor.setOption('extraKeys', {
      'Ctrl-B': function(cm) {
        toggleMarkdown(cm, '**');
      },
      'Ctrl-I': function(cm) {
        toggleMarkdown(cm, '*');
      },
      'Ctrl-S': function(cm) {
        window.chrome.webview.postMessage('SAVE_REQUESTED');
      }
    });
    
    function toggleMarkdown(cm, wrapper) {
      const selection = cm.getSelection();
      if (selection.startsWith(wrapper) && selection.endsWith(wrapper)) {
        cm.replaceSelection(selection.slice(wrapper.length, -wrapper.length));
      } else {
        cm.replaceSelection(wrapper + selection + wrapper);
      }
    }
    
    // 준비 완료 알림
    setTimeout(function() {
      window.chrome.webview.postMessage('READY');
    }, 100);
  </script>
</body>
</html>
    ''';
  }

  // 외부에서 호출할 수 있는 메서드들
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
      } catch (e) {
        print('setText 오류: $e');
      }
    }
  }

  Future<String> getText() async {
    if (isLoading || !_isInitialized) return _currentText;

    try {
      final result = await _controller.executeScript('window.getText()');
      return result?.toString().replaceAll('"', '') ?? _currentText;
    } catch (e) {
      print('getText 오류: $e');
      return _currentText;
    }
  }

  Future<void> insertText(String text) async {
    if (!_isInitialized) return;

    final escaped = text.replaceAll("'", "\\'");
    try {
      await _controller.executeScript("window.insertText('$escaped')");
    } catch (e) {
      print('insertText 오류: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 명확한 높이 계산
        final height =
            constraints.maxHeight == double.infinity
                ? MediaQuery.of(context).size.height - 100
                : constraints.maxHeight;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              if (_isInitialized)
                webview_windows.Webview(_controller)
              else
                Container(color: Theme.of(context).scaffoldBackgroundColor),
              if (isLoading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        );
      },
    );
  }
}
