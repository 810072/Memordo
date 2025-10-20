// lib/widgets/codemirror_editor.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

// 플랫폼별 import
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart';

// ✨ [추가] 상수 정의
class EditorConfig {
  static const int maxRetries = 3;
  static const Duration initialTimeout = Duration(seconds: 2);
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration windowsTimeout = Duration(seconds: 15);
}

// ✨ [추가] 추상 인터페이스
abstract class WebViewController {
  Future<void> executeScript(String script);
  Future<String?> executeScriptReturningResult(String script);
  void dispose();
}

// ✨ [추가] Windows WebView 컨트롤러 래퍼
class WindowsWebViewController implements WebViewController {
  final WebviewController _controller;

  WindowsWebViewController(this._controller);

  @override
  Future<void> executeScript(String script) async {
    await _controller.executeScript(script);
  }

  @override
  Future<String?> executeScriptReturningResult(String script) async {
    final result = await _controller.executeScript(script);
    return result?.toString();
  }

  @override
  void dispose() {
    _controller.dispose();
  }
}

// ✨ [추가] 크로스플랫폼 WebView 컨트롤러 래퍼
class CrossPlatformWebViewController implements WebViewController {
  final wf.WebViewController _controller;

  CrossPlatformWebViewController(this._controller);

  @override
  Future<void> executeScript(String script) async {
    await _controller.runJavaScript(script);
  }

  @override
  Future<String?> executeScriptReturningResult(String script) async {
    final result = await _controller.runJavaScriptReturningResult(script);
    return result.toString().replaceAll('"', '');
  }

  @override
  void dispose() {
    // webview_flutter의 WebViewController는 dispose가 필요 없음
  }
}

class CodeMirrorEditor extends StatefulWidget {
  final TextEditingController? controller;
  final VoidCallback? onSaveRequested;
  final Function(String query, double dx, double dy)?
  onWikiLinkSuggestionsRequested;
  final VoidCallback? onHideWikiLinkSuggestions;
  final Function(int index)? onHighlightSuggestion;
  final VoidCallback? onSelectSuggestion;
  final Function(String fileName)? onWikiLinkClicked; // ✨ [추가]

  const CodeMirrorEditor({
    super.key,
    this.controller,
    this.onSaveRequested,
    this.onWikiLinkSuggestionsRequested,
    this.onHideWikiLinkSuggestions,
    this.onHighlightSuggestion,
    this.onSelectSuggestion,
    this.onWikiLinkClicked, // ✨ [추가]
  });

  @override
  State<CodeMirrorEditor> createState() => CodeMirrorEditorState();
}

class CodeMirrorEditorState extends State<CodeMirrorEditor> {
  // ✨ [수정] 타입 안전성 강화
  WebViewController? _controller;
  bool _isWindows = false;

  bool isLoading = true;
  String _currentText = '';
  bool _isInitialized = false;
  String? _errorMessage;

  // ✨ [추가] 재시도 카운터
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _currentText = widget.controller?.text ?? '';
    widget.controller?.addListener(_onControllerChanged);

    // ✨ [수정] 플랫폼 확인 (try-catch 추가)
    try {
      if (!kIsWeb && Platform.isWindows) {
        _isWindows = true;
      }
    } catch (e) {
      debugPrint('플랫폼 확인 오류: $e');
      _isWindows = false;
    }

    _initWebView();
  }

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
      final newText = widget.controller?.text ?? '';
      if (_currentText != newText) {
        setText(newText);
      }
    }
  }

  void toggleFormatting(bool show) {
    if (!_isInitialized || _controller == null) return;
    try {
      _controller!.executeScript("window.toggleFormatting($show)");
    } catch (e) {
      debugPrint('toggleFormatting 오류: $e');
    }
  }

  Future<void> _initWebView() async {
    try {
      if (_isWindows) {
        await _initWindowsWebViewWithRetry();
      } else {
        await _initCrossPlatformWebView();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          _errorMessage = '에디터 로드 실패: $e';
        });
      }
    }
  }

  // ✨ [추가] 재시도 메커니즘
  Future<void> _initWindowsWebViewWithRetry() async {
    for (int attempt = 0; attempt < EditorConfig.maxRetries; attempt++) {
      _retryCount = attempt;
      try {
        await _initWindowsWebView();
        return; // 성공 시 반환
      } catch (e) {
        if (attempt == EditorConfig.maxRetries - 1) {
          rethrow; // 마지막 시도에서는 예외 전파
        }
        if (mounted) {
          setState(() {
            _errorMessage =
                'WebView 초기화 실패 (재시도 ${attempt + 1}/${EditorConfig.maxRetries})...\n'
                'Microsoft Edge WebView2 런타임이 설치되어 있는지 확인해주세요.';
          });
        }
        await Future.delayed(EditorConfig.retryDelay * (attempt + 1));
      }
    }
  }

  Future<void> _initWindowsWebView() async {
    final webviewController = WebviewController();

    await webviewController.initialize();

    webviewController.webMessage.listen((message) {
      _handleWebMessage(message);
    });

    final htmlContent = await _getHtmlWithLocalAssets();
    await webviewController.loadStringContent(htmlContent);

    // ✨ [수정] 타입 안전한 컨트롤러 할당
    _controller = WindowsWebViewController(webviewController);

    // 타임아웃 설정
    Future.delayed(EditorConfig.windowsTimeout, () {
      if (isLoading && mounted) {
        setState(() {
          isLoading = false;
          _errorMessage =
              'WebView 초기화 시간 초과.\n'
              'Microsoft Edge WebView2 런타임이 설치되어 있는지 확인해주세요.';
        });
      }
    });
  }

  Future<void> _initCrossPlatformWebView() async {
    final controller =
        wf.WebViewController()
          ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.white)
          ..addJavaScriptChannel(
            'FlutterChannel',
            onMessageReceived: (wf.JavaScriptMessage message) {
              _handleWebMessage(message.message);
            },
          );

    // ✨ [수정] 타입 안전한 컨트롤러 할당
    _controller = CrossPlatformWebViewController(controller);

    final htmlContent = await _getHtmlWithLocalAssetsCrossPlatform();
    await controller.loadHtmlString(htmlContent);

    // 초기화 확인
    Future.delayed(EditorConfig.initialTimeout, () {
      if (mounted && !_isInitialized) {
        setState(() {
          isLoading = false;
          _isInitialized = true;
        });
        if (_currentText.isNotEmpty) {
          setText(_currentText);
        }
      }
    });
  }

  // ✨ [추가] 통합 메시지 핸들러
  void _handleWebMessage(String message) {
    try {
      final data = jsonDecode(message);
      _handleJsonMessage(data);
    } catch (e) {
      _handleTextMessage(message);
    }
  }

  void _handleJsonMessage(Map<String, dynamic> data) async {
    if (!mounted) return;

    switch (data['type']) {
      case 'update':
        final newText = data['text'] as String;
        final newOffset = data['offset'] as int;
        _currentText = newText;
        if (widget.controller != null) {
          widget.controller!.removeListener(_onControllerChanged);
          widget.controller!.value = TextEditingValue(
            text: newText,
            selection: TextSelection.fromPosition(
              TextPosition(offset: newOffset),
            ),
          );
          widget.controller!.addListener(_onControllerChanged);
        }
        break;
      case 'show-wikilink':
        widget.onWikiLinkSuggestionsRequested?.call(
          data['query'] as String,
          (data['x'] as num).toDouble(),
          (data['y'] as num).toDouble(),
        );
        break;
      case 'hide-wikilink':
        widget.onHideWikiLinkSuggestions?.call();
        break;
      case 'highlight-suggestion':
        widget.onHighlightSuggestion?.call(data['index'] as int);
        break;
      case 'select-suggestion':
        widget.onSelectSuggestion?.call();
        break;
      case 'open-url':
        final url = data['url'] as String?;
        if (url != null && url.isNotEmpty) {
          _openUrl(url);
        }
        break;
      // ✨ [추가] 위키링크 처리
      case 'open-wikilink':
        final fileName = data['fileName'] as String?;
        if (fileName != null && fileName.isNotEmpty) {
          widget.onWikiLinkClicked?.call(fileName);
        }
        break;
      default:
        debugPrint('알 수 없는 메시지 타입: ${data['type']}');
    }
  }

  void _handleTextMessage(String message) {
    if (!mounted) return;

    if (message == 'READY') {
      setState(() {
        isLoading = false;
        _isInitialized = true;
        _errorMessage = null;
      });
      if (_currentText.isNotEmpty) {
        setText(_currentText);
      }
    } else if (message == 'SAVE_REQUESTED') {
      widget.onSaveRequested?.call();
    } else if (message.startsWith('ERROR:')) {
      setState(() {
        isLoading = false;
        _errorMessage = message;
      });
    }
  }

  // ✨ [추가] URL 열기 메서드 분리
  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        debugPrint('유효하지 않은 URL: $url');
      }
    } catch (e) {
      debugPrint('URL 열기 오류: $e');
    }
  }

  // ✨ [수정] _getHtmlWithLocalAssets 메서드 업데이트
  Future<String> _getHtmlWithLocalAssets() async {
    final cssCodemirror = await rootBundle.loadString(
      'assets/codemirror/codemirror.min.css',
    );
    final cssTheme = await rootBundle.loadString(
      'assets/codemirror/material-darker.min.css',
    );
    final jsCodemirror = await rootBundle.loadString(
      'assets/codemirror/codemirror.min.js',
    );
    final jsOverlay = await rootBundle.loadString(
      'assets/codemirror/overlay.min.js',
    );
    final jsXml = await rootBundle.loadString('assets/codemirror/xml.min.js');
    final jsMarkdown = await rootBundle.loadString(
      'assets/codemirror/markdown.min.js',
    );
    final jsGfm = await rootBundle.loadString('assets/codemirror/gfm.min.js');

    // ✨ [추가] JavaScript 통합 파일 로드
    final jsIntegration = await _loadEditorIntegrationJs(useWindowsApi: true);

    return _buildHtmlWithSeparateJs(
      cssCodemirror,
      cssTheme,
      jsCodemirror,
      jsOverlay,
      jsXml,
      jsMarkdown,
      jsGfm,
      jsIntegration,
    );
  }

  // ✨ [추가] JavaScript 파일 로드 메서드
  Future<String> _loadEditorIntegrationJs({required bool useWindowsApi}) async {
    final jsIntegration = await rootBundle.loadString(
      'assets/codemirror/editor_integration.js',
    );

    // PostMessage API 교체
    final postMessageApi =
        useWindowsApi
            ? 'window.chrome.webview.postMessage'
            : 'window.FlutterChannel.postMessage';

    return jsIntegration.replaceAll(
      'const postMessage = typeof window.chrome',
      'const postMessage = $postMessageApi; // const postMessage = typeof window.chrome',
    );
  }

  // ✨ [수정] _getHtmlWithLocalAssetsCrossPlatform 메서드 업데이트
  Future<String> _getHtmlWithLocalAssetsCrossPlatform() async {
    final cssCodemirror = await rootBundle.loadString(
      'assets/codemirror/codemirror.min.css',
    );
    final cssTheme = await rootBundle.loadString(
      'assets/codemirror/material-darker.min.css',
    );
    final jsCodemirror = await rootBundle.loadString(
      'assets/codemirror/codemirror.min.js',
    );
    final jsOverlay = await rootBundle.loadString(
      'assets/codemirror/overlay.min.js',
    );
    final jsXml = await rootBundle.loadString('assets/codemirror/xml.min.js');
    final jsMarkdown = await rootBundle.loadString(
      'assets/codemirror/markdown.min.js',
    );
    final jsGfm = await rootBundle.loadString('assets/codemirror/gfm.min.js');

    // ✨ [추가] JavaScript 통합 파일 로드
    final jsIntegration = await _loadEditorIntegrationJs(useWindowsApi: false);

    return _buildHtmlWithSeparateJs(
      cssCodemirror,
      cssTheme,
      jsCodemirror,
      jsOverlay,
      jsXml,
      jsMarkdown,
      jsGfm,
      jsIntegration,
    );
  }

  // ✨ [수정] 간소화된 HTML 빌드
  String _buildHtmlWithSeparateJs(
    String cssCodemirror,
    String cssTheme,
    String jsCodemirror,
    String jsOverlay,
    String jsXml,
    String jsMarkdown,
    String jsGfm,
    String jsIntegration,
  ) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>$cssCodemirror $cssTheme</style>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #ffffff; overflow: hidden; }
    .CodeMirror { 
      height: 100vh; 
      font-size: 16px; 
      font-family: -apple-system, system-ui, sans-serif; 
      line-height: 1.6; 
    }
    .CodeMirror-scroll { padding: 16px; }
    .CodeMirror-cursor { border-left: 2px solid #000000 !important; }
    .CodeMirror-selected { background: rgba(59, 130, 246, 0.2) !important; }
    .cm-header, .cm-quote, .cm-keyword, .cm-variable-2 { 
      color: inherit !important; 
    }
    .cm-comment, .cm-meta { font-family: 'Consolas', monospace; }
    span.cm-comment { 
      background-color: rgba(100, 100, 100, 0.1); 
      border-radius: 4px; 
      padding: 0.1em 0.3em; 
    }
    .code-block-background { 
      background-color: rgba(100, 100, 100, 0.05); 
      border-radius: 4px; 
      padding: 2px 0; 
    }
    .cm-header-1 { font-size: 2em; font-weight: 700; }
    .cm-header-2 { font-size: 1.5em; font-weight: 700; }
    .cm-header-3 { font-size: 1.3em; font-weight: 600; }
    .cm-strong { font-weight: 700; }
    .cm-em { font-style: italic; }
    .cm-strikethrough { text-decoration: line-through; }
    .cm-link, .cm-url { 
      color: #3498db; 
      text-decoration: underline; 
      cursor: pointer; 
      transition: color 0.2s ease;
    }
    .cm-link:hover, .cm-url:hover {
      color: #2980b9;
      text-decoration: underline;
    }
    
    /* ✨ 위키링크 브래킷은 항상 표시 */
    .cm-wikilink-bracket {
      color: #3498db;
      font-weight: bold;
    }
    
    /* ✨ 수정된 문법 숨김/표시 CSS */
    /* 기본: 모든 문법 기호 보임 */
    .cm-formatting { 
      display: inline;
      font-size: inherit;
      color: inherit;
    }
    
    /* 링크 URL 전체 숨김 */
    .cm-formatting-link-url {
      display: inline;
      font-size: inherit;
      color: inherit;
    }
    
    /* hide-formatting 모드: 문법 숨김 */
    .hide-formatting .cm-formatting { 
      position: absolute;
      width: 0;
      height: 0;
      overflow: hidden;
      font-size: 0 !important;
      line-height: 0 !important;
      opacity: 0 !important;
      pointer-events: none !important;
    }
    
    /* hide-formatting 모드: 링크 URL 완전히 숨김 */
    .hide-formatting .cm-formatting-link-url {
      position: absolute;
      width: 0;
      height: 0;
      overflow: hidden;
      font-size: 0 !important;
      line-height: 0 !important;
      opacity: 0 !important;
      pointer-events: none !important;
    }
    
    /* ✨ 현재 라인에서는 표시 (JavaScript에서 추가하는 클래스 사용) */
    .hide-formatting .active-line-formatting .cm-formatting { 
      position: static !important;
      width: auto !important;
      height: auto !important;
      overflow: visible !important;
      font-size: inherit !important;
      line-height: inherit !important;
      opacity: 1 !important;
      pointer-events: auto !important;
    }
    
    /* ✨ 현재 라인에서도 링크 URL은 숨김 유지 */
    .hide-formatting .active-line-formatting .cm-formatting-link-url {
      position: absolute !important;
      width: 0 !important;
      height: 0 !important;
      overflow: hidden !important;
      font-size: 0 !important;
      line-height: 0 !important;
      opacity: 0 !important;
      pointer-events: none !important;
    }
  </style>
</head>
<body>
  <textarea id="editor"></textarea>
  
  <script>$jsCodemirror</script>
  <script>$jsOverlay</script>
  <script>$jsXml</script>
  <script>$jsMarkdown</script>
  <script>$jsGfm</script>
  <script>$jsIntegration</script>
</body>
</html>
  ''';
  }

  void updateSuggestionCount(int count) {
    if (!_isInitialized || _controller == null) return;
    try {
      _controller!.executeScript("window.updateSuggestionCount($count)");
    } catch (e) {
      debugPrint('updateSuggestionCount 오류: $e');
    }
  }

  Future<void> insertWikiLink(String fileName) async {
    if (!_isInitialized || _controller == null) return;
    final escapedFileName = fileName
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"')
        .replaceAll('\n', '')
        .replaceAll('\r', '');
    try {
      await _controller!.executeScript(
        "window.insertWikiLink('$escapedFileName')",
      );
    } catch (e) {
      debugPrint('insertWikiLink 오류: $e');
    }
  }

  Future<void> setText(String text) async {
    _currentText = text;
    if (_isInitialized && !isLoading && _controller != null) {
      final escaped = text
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "\\'")
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '');
      try {
        await _controller!.executeScript("window.setText('$escaped')");
      } catch (e) {
        debugPrint('setText 오류: $e');
      }
    }
  }

  Future<String> getText() async {
    if (isLoading || !_isInitialized || _controller == null) {
      return _currentText;
    }
    try {
      final result = await _controller!.executeScriptReturningResult(
        'window.getText()',
      );
      return result ?? _currentText;
    } catch (e) {
      debugPrint('getText 오류: $e');
      return _currentText;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✨ [추가] 플랫폼별 WebView 위젯 빌드
    Widget webViewWidget;
    if (_isWindows && _controller is WindowsWebViewController) {
      webViewWidget = Webview(
        (_controller as WindowsWebViewController)._controller,
      );
    } else if (_controller is CrossPlatformWebViewController) {
      webViewWidget = wf.WebViewWidget(
        controller: (_controller as CrossPlatformWebViewController)._controller,
      );
    } else {
      webViewWidget = Container(
        color: Theme.of(context).scaffoldBackgroundColor,
      );
    }

    return Stack(
      children: [
        if (!_isInitialized)
          Container(color: Theme.of(context).scaffoldBackgroundColor),
        webViewWidget,
        if (isLoading || _errorMessage != null)
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(
              child:
                  _errorMessage != null
                      ? Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            SelectableText(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                            if (_retryCount < EditorConfig.maxRetries - 1) ...[
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('다시 시도'),
                                onPressed: () {
                                  setState(() {
                                    isLoading = true;
                                    _errorMessage = null;
                                  });
                                  _initWebView();
                                },
                              ),
                            ],
                          ],
                        ),
                      )
                      : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('에디터 로드 중...'),
                        ],
                      ),
            ),
          ),
      ],
    );
  }
}
