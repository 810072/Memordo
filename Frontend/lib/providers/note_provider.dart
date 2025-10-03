// lib/providers/note_provider.dart
import 'package:flutter/material.dart';

// Header 정보를 담을 데이터 클래스
class HeaderInfo {
  final String text;
  final int level;
  final int position;

  HeaderInfo({required this.text, required this.level, required this.position});
}

class NoteProvider with ChangeNotifier {
  TextEditingController? _controller;
  FocusNode? _focusNode;

  void Function(String)? onNewMemoFromHistory;

  int _currentLine = 0;
  int _currentChar = 0;
  int _totalChars = 0;
  int _totalLineChars = 0;

  int get currentLine => _currentLine;
  int get currentChar => _currentChar;
  int get totalChars => _totalChars;
  int get totalLineChars => _totalLineChars;

  void requestNewMemoFromHistory(String text) {
    onNewMemoFromHistory?.call(text);
  }

  TextEditingController? get controller => _controller;

  // 컨트롤러와 포커스 노드를 등록하는 메서드
  void register(TextEditingController controller, FocusNode focusNode) {
    if (_controller != null) {
      _controller!.removeListener(_onTextChanged);
    }
    _controller = controller;
    _focusNode = focusNode;
    _controller!.addListener(_onTextChanged);

    // ✨ [수정] build가 끝난 직후에 실행되도록 변경하여 에러를 해결합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onTextChanged();
    });
  }

  // 텍스트가 변경되었음을 알리는 내부 메서드
  void _onTextChanged() {
    if (_controller != null) {
      final text = _controller!.text;
      final offset = _controller!.selection.baseOffset;

      _totalChars = text.length;

      if (offset >= 0 && offset <= text.length) {
        final textBeforeCursor = text.substring(0, offset);
        final lines = textBeforeCursor.split('\n');
        _currentLine = lines.length;
        _currentChar = lines.isNotEmpty ? lines.last.length + 1 : 1;

        final allLines = text.split('\n');
        if (_currentLine > 0 && _currentLine <= allLines.length) {
          _totalLineChars = allLines[_currentLine - 1].length;
        } else {
          _totalLineChars = 0;
        }
      } else {
        _currentLine = 1;
        _currentChar = 1;
        _totalLineChars = 0;
      }
    } else {
      _currentLine = 0;
      _currentChar = 0;
      _totalChars = 0;
      _totalLineChars = 0;
    }
    notifyListeners();
  }

  // 특정 위치로 커서를 이동시키는 메서드
  void jumpTo(int offset) {
    if (_controller != null && _focusNode != null) {
      _controller!.selection = TextSelection.fromPosition(
        TextPosition(offset: offset),
      );
      _focusNode!.requestFocus();
    }
  }

  // 마크다운 헤더를 파싱하는 로직
  List<HeaderInfo> parseHeaders() {
    if (_controller == null) return [];
    final text = _controller!.text;
    final lines = text.split('\n');
    final headers = <HeaderInfo>[];
    int currentPosition = 0;

    final headerRegex = RegExp(r'^(#{1,6})\s+(.*)');

    for (final line in lines) {
      final match = headerRegex.firstMatch(line);
      if (match != null) {
        final level = match.group(1)!.length;
        final headerText = match.group(2)!.trim();
        headers.add(
          HeaderInfo(text: headerText, level: level, position: currentPosition),
        );
      }
      currentPosition += line.length + 1;
    }
    return headers;
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTextChanged);
    super.dispose();
  }
}
