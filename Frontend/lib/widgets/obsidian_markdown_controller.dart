// lib/widgets/obsidian_markdown_controller.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// A TextEditingController that applies markdown-like styling to the text in real-time.
///
/// This controller uses a listener-based approach to handle smart editing features
/// like list continuation and provides methods for programmatic styling changes,
/// ensuring high performance and cursor stability.
class ObsidianMarkdownController extends TextEditingController {
  // ✨ [수정] _styleMap을 final이 아닌 일반 멤버 변수로 변경하여 업데이트가 가능하도록 합니다.
  Map<String, TextStyle> _styleMap;
  TextEditingValue _previousValue = const TextEditingValue();
  bool _isProgrammaticChange = false;

  // Regex for styling and smart editing features.
  // 헤더, 리스트, 인용구의 정규식을 수정하여 마커, 공백, 내용을 별도의 그룹으로 캡처하도록 변경했습니다.
  static final Map<String, RegExp> _stylingRegexMap = {
    'header': RegExp(r'^(#{1,6})(\s+)(.*)', multiLine: true),
    'list': RegExp(r'^(\s*[-*+•]|\s*\d+\.)(\s+)(.*)', multiLine: true),
    'quote': RegExp(r'^(>)(\s+)(.*)', multiLine: true),
    'link': RegExp(r'\[(.*?)\]\((.*?)\)', dotAll: true),
    'code': RegExp(r'`(.*?)`', dotAll: true),
    'bold': RegExp(r'\*\*(.*?)\*\*', dotAll: true),
    'strikethrough': RegExp(r'~~(.*?)~~', dotAll: true),
    'italic': RegExp(r'(?<![*\w])\*(?!\*)(.*?[^\s*])\*(?![*\w])', dotAll: true),
  };
  static final RegExp _listContinuationRegex = RegExp(
    r'^(\s*)([-*+]|\d+\.)\s+(.*)$',
  );

  ObsidianMarkdownController({
    String? text,
    required Map<String, TextStyle> styleMap,
  }) : _styleMap = styleMap,
       super(text: text) {
    _previousValue = value;
    addListener(_mainListener);
  }

  // ✨ [추가] 외부에서 스타일 맵을 업데이트하고, UI 갱신을 트리거하는 메서드
  void updateStyles(Map<String, TextStyle> newStyles) {
    // 스타일이 실제로 변경되었는지 확인하여 불필요한 재빌드를 방지합니다. (선택적 최적화)
    if (newStyles.toString() != _styleMap.toString()) {
      _styleMap = newStyles;
      // notifyListeners()를 호출하여 컨트롤러를 사용하는 TextField가
      // buildTextSpan을 다시 호출하도록 강제합니다.
      notifyListeners();
    }
  }

  @override
  void dispose() {
    removeListener(_mainListener);
    super.dispose();
  }

  /// Main listener to detect text changes and dispatch handlers.
  void _mainListener() {
    if (_isProgrammaticChange) {
      _isProgrammaticChange = false;
      _previousValue = value;
      return;
    }

    if (value.text == _previousValue.text &&
        value.selection == _previousValue.selection) {
      return;
    }

    // Handle Enter key press for list continuation
    if (text.length > _previousValue.text.length &&
        text.substring(_previousValue.selection.start, selection.start) ==
            '\n') {
      _handleEnterKey();
    }

    _previousValue = value;
  }

  /// Handles automatic list continuation when Enter is pressed.
  void _handleEnterKey() {
    final currentLineIndex = selection.baseOffset - 1;
    if (currentLineIndex < 0) return;

    final startOfLine = text.lastIndexOf('\n', currentLineIndex) + 1;
    final currentLine = text.substring(startOfLine, currentLineIndex + 1);
    final match = _listContinuationRegex.firstMatch(currentLine);

    if (match != null) {
      final indent = match.group(1) ?? '';
      final marker = match.group(2) ?? '';
      final content = match.group(3) ?? '';

      // If the list item content is empty, terminate the list.
      if (content.trim().isEmpty) {
        _runProgrammaticChange(() {
          final textBefore = text.substring(0, startOfLine);
          final textAfter = text.substring(selection.end);
          this.text = textBefore + textAfter; // Remove the list item line
          selection = TextSelection.fromPosition(
            TextPosition(offset: startOfLine),
          );
        });
        return;
      }

      String newMarker;
      if (int.tryParse(marker.replaceAll('.', '')) != null) {
        final number = int.parse(marker.replaceAll('.', ''));
        newMarker = '${number + 1}.';
      } else {
        newMarker = marker;
      }

      final textToInsert = '\n$indent$newMarker ';

      _runProgrammaticChange(() {
        final newText =
            text.substring(0, selection.start) +
            textToInsert.substring(1) + // Insert text without extra newline
            text.substring(selection.end);
        final newOffset = selection.start + textToInsert.length - 1;

        value = TextEditingValue(
          text: newText,
          selection: TextSelection.fromPosition(
            TextPosition(offset: newOffset),
          ),
        );
      });
    }
  }

  /// Runs a programmatic text change and prevents listener loops.
  void _runProgrammaticChange(VoidCallback action) {
    _isProgrammaticChange = true;
    action();
  }

  /// Toggles inline markdown syntax for the current selection.
  void toggleInlineSyntax(String prefix, String suffix) {
    _runProgrammaticChange(() {
      final currentSelection = selection;
      final selectedText = currentSelection.textInside(text);
      final textBefore = currentSelection.textBefore(text);
      final textAfter = currentSelection.textAfter(text);

      final startsWith = selectedText.startsWith(prefix);
      final endsWith = selectedText.endsWith(suffix);

      String newText;
      int newStart = currentSelection.start;
      int newEnd;

      if (startsWith && endsWith) {
        // Remove syntax
        newText = selectedText.substring(
          prefix.length,
          selectedText.length - suffix.length,
        );
        newEnd = newStart + newText.length;
      } else {
        // Add syntax
        newText = '$prefix$selectedText$suffix';
        newEnd = newStart + newText.length;
      }

      value = value.copyWith(
        text: textBefore + newText + textAfter,
        selection: TextSelection(baseOffset: newStart, extentOffset: newEnd),
        composing: TextRange.empty,
      );
    });
  }

  /// Adjusts the indentation level of a list item.
  void indentList(bool isIndent) {
    _runProgrammaticChange(() {
      final currentSelection = selection;
      // ✨ 커서가 맨 앞일 경우, 들여쓰기를 실행하지 않도록 수정
      if (currentSelection.start == 0) return;
      final startOfLine =
          text.lastIndexOf('\n', currentSelection.start - 1) + 1;
      final endOfLine = text.indexOf('\n', startOfLine);
      final lineEnd = endOfLine == -1 ? text.length : endOfLine;
      final currentLine = text.substring(startOfLine, lineEnd);

      final match = _listContinuationRegex.firstMatch(currentLine);
      if (match == null && !isIndent) return; // Can't outdent non-list item

      String newText;
      int offsetChange;

      if (isIndent) {
        newText = '  ' + currentLine;
        offsetChange = 2;
      } else {
        if (currentLine.startsWith('  ')) {
          newText = currentLine.substring(2);
          offsetChange = -2;
        } else if (currentLine.startsWith(' ')) {
          newText = currentLine.substring(1);
          offsetChange = -1;
        } else {
          return; // No indentation to remove
        }
      }

      value = value.copyWith(
        text: text.replaceRange(startOfLine, lineEnd, newText),
        selection: currentSelection.copyWith(
          baseOffset: currentSelection.baseOffset + offsetChange,
          extentOffset: currentSelection.extentOffset + offsetChange,
        ),
        composing: TextRange.empty,
      );
    });
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final defaultStyle = style ?? const TextStyle();
    if (text.isEmpty) {
      return TextSpan(text: '', style: defaultStyle);
    }

    final List<_Match> allMatches = [];

    _stylingRegexMap.forEach((type, regex) {
      for (final match in regex.allMatches(text)) {
        allMatches.add(_Match(match, type));
      }
    });

    allMatches.sort((a, b) {
      if (a.match.start < b.match.start) return -1;
      if (a.match.start > b.match.start) return 1;
      if (a.match.end > b.match.end) return -1;
      if (a.match.end < b.match.end) return 1;
      return 0;
    });

    final List<_Match> filteredMatches = [];
    int lastEnd = -1;
    for (final currentMatch in allMatches) {
      if (currentMatch.match.start >= lastEnd) {
        filteredMatches.add(currentMatch);
        lastEnd = currentMatch.match.end;
      }
    }

    if (filteredMatches.isEmpty) {
      return TextSpan(text: text, style: defaultStyle);
    }

    final List<TextSpan> spans = [];
    int currentIndex = 0;

    for (final item in filteredMatches) {
      if (item.match.start > currentIndex) {
        spans.add(
          TextSpan(
            text: text.substring(currentIndex, item.match.start),
            style: defaultStyle,
          ),
        );
      }
      spans.add(_createStyledSpan(item.match, item.type, defaultStyle));
      currentIndex = item.match.end;
    }

    if (currentIndex < text.length) {
      spans.add(
        TextSpan(text: text.substring(currentIndex), style: defaultStyle),
      );
    }

    return TextSpan(children: spans, style: defaultStyle);
  }

  /// This method now separates markdown syntax from content to apply different styles.
  /// This preserves the original text length and structure, fixing cursor position issues.
  TextSpan _createStyledSpan(
    RegExpMatch match,
    String type,
    TextStyle defaultStyle,
  ) {
    TextStyle style;
    if (type == 'header') {
      final headerLevel = match.group(1)!.length;
      style = _styleMap['h$headerLevel'] ?? _styleMap['h3'] ?? defaultStyle;
    } else {
      style = _styleMap[type] ?? defaultStyle;
    }

    // Style for markdown syntax characters (e.g., '#', '**')
    final syntaxStyle = TextStyle(color: Colors.grey.shade400);

    switch (type) {
      case 'bold':
        return TextSpan(
          children: [
            TextSpan(text: '**', style: syntaxStyle),
            TextSpan(text: match.group(1) ?? '', style: style),
            TextSpan(text: '**', style: syntaxStyle),
          ],
        );
      case 'italic':
        return TextSpan(
          children: [
            TextSpan(text: '*', style: syntaxStyle),
            TextSpan(text: match.group(1) ?? '', style: style),
            TextSpan(text: '*', style: syntaxStyle),
          ],
        );
      case 'strikethrough':
        return TextSpan(
          children: [
            TextSpan(text: '~~', style: syntaxStyle),
            TextSpan(text: match.group(1) ?? '', style: style),
            TextSpan(text: '~~', style: syntaxStyle),
          ],
        );
      case 'code':
        return TextSpan(
          style: style, // Apply background color to the whole span
          children: [
            TextSpan(
              text: '`',
              style: syntaxStyle.copyWith(backgroundColor: Colors.transparent),
            ),
            TextSpan(text: match.group(1) ?? ''), // Inherits parent's style
            TextSpan(
              text: '`',
              style: syntaxStyle.copyWith(backgroundColor: Colors.transparent),
            ),
          ],
        );
      case 'link':
        final linkText = match.group(1) ?? '';
        final url = match.group(2) ?? '';
        return TextSpan(
          children: [
            TextSpan(text: '[', style: syntaxStyle),
            TextSpan(
              text: linkText,
              style: style,
              recognizer:
                  TapGestureRecognizer()
                    ..onTap = () async {
                      final uri = Uri.tryParse(url);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
            ),
            TextSpan(text: '](', style: syntaxStyle),
            TextSpan(text: url, style: syntaxStyle),
            TextSpan(text: ')', style: syntaxStyle),
          ],
        );

      case 'header':
      case 'list':
      case 'quote':
        final marker = match.group(1) ?? '';
        final space = match.group(2) ?? '';
        final content = match.group(3) ?? '';
        return TextSpan(
          style:
              style, // Apply main style (font size, height) to the whole line
          children: [
            // 마커는 부모 스타일(크기)을 상속받되, 색상만 변경합니다.
            TextSpan(
              text: marker,
              style: syntaxStyle.copyWith(
                fontSize: style.fontSize,
                height: style.height,
              ),
            ),
            // 공백과 내용은 부모의 스타일을 그대로 상속받습니다.
            TextSpan(text: space),
            TextSpan(text: content),
          ],
        );
      default:
        // Fallback for any unhandled types
        return TextSpan(text: match.group(0)!, style: defaultStyle);
    }
  }
}

// Helper class to hold match data
class _Match {
  final RegExpMatch match;
  final String type;

  _Match(this.match, this.type);
}
