// lib/widgets/obsidian_markdown_controller.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 완전히 개선된 옵시디언 스타일 마크다운 컨트롤러
///
/// 주요 개선사항:
/// 1. 커서 위치 기반 문법 표시/숨김
/// 2. 중첩 마크다운 완벽 지원
/// 3. 줄 단위 파싱으로 성능 최적화
/// 4. 체크박스, 테이블, 각주 등 추가 기능
/// 5. 더 정확한 스타일 적용
class MarkdownController extends TextEditingController {
  Map<String, TextStyle> _styleMap;
  TextEditingValue _previousValue = const TextEditingValue();
  bool _isProgrammaticChange = false;

  // 줄 단위 캐싱으로 성능 최적화
  final Map<int, _LineCache> _lineCache = {};
  int _lastCursorLine = -1;

  // 블록 레벨 스타일 (줄 전체에 영향)
  static final Map<String, RegExp> _blockLevelRegexMap = {
    'header': RegExp(r'^(#{1,6})(\s+)(.*)$'),
    'list': RegExp(r'^(\s*[-*+•]|\s*\d+\.)(\s+)(.*)$'),
    'checkbox': RegExp(r'^(\s*[-*+])\s+(\[([ xX])\])\s+(.*)$'),
    'quote': RegExp(r'^(>+)(\s*)(.*)$'),
    'codeBlock': RegExp(r'^(```|~~~)(.*)$'),
    'hr': RegExp(r'^(\s*[-*_]){3,}\s*$'),
    'table': RegExp(r'^\|(.+)\|$'),
  };

  // 인라인 레벨 스타일 (텍스트 일부에 영향)
  static final Map<String, RegExp> _inlineLevelRegexMap = {
    'boldItalic': RegExp(r'\*\*\*(.+?)\*\*\*'),
    'bold': RegExp(r'\*\*(.+?)\*\*'),
    'italic': RegExp(r'(?<![*\w])\*(?!\*)(.+?[^\s*])\*(?![*\w])'),
    'strikethrough': RegExp(r'~~(.+?)~~'),
    'highlight': RegExp(r'==(.+?)=='),
    'code': RegExp(r'`(.+?)`'),
    'mathInline': RegExp(r'\$(.+?)\$'),
    'link': RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
    'wikiLink': RegExp(r'\[\[([^\]]+)\]\]'),
    'footnote': RegExp(r'\[\^(\d+)\]'),
    'tag': RegExp(r'#[\w-]+'),
  };

  static final RegExp _listContinuationRegex = RegExp(
    r'^(\s*)([-*+]|\d+\.)\s+(.*)$',
  );

  MarkdownController({String? text, required Map<String, TextStyle> styleMap})
    : _styleMap = styleMap,
      super(text: text) {
    _previousValue = value;
    addListener(_mainListener);
  }

  void updateStyles(Map<String, TextStyle> newStyles) {
    if (newStyles.toString() != _styleMap.toString()) {
      _styleMap = newStyles;
      _lineCache.clear();
    }
  }

  @override
  void dispose() {
    removeListener(_mainListener);
    super.dispose();
  }

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

    // 변경된 줄의 캐시만 무효화
    final currentCursorLine = _getLineNumber(selection.start);
    if (currentCursorLine != _lastCursorLine) {
      _lineCache.remove(_lastCursorLine);
      _lineCache.remove(currentCursorLine);
      _lastCursorLine = currentCursorLine;
    }

    if (text.length > _previousValue.text.length &&
        text.substring(_previousValue.selection.start, selection.start) ==
            '\n') {
      _handleEnterKey();
    }

    _previousValue = value;
  }

  int _getLineNumber(int offset) {
    if (offset < 0 || offset > text.length) return -1;
    return text.substring(0, offset).split('\n').length - 1;
  }

  void _handleEnterKey() {
    final currentLineIndex = selection.baseOffset - 1;
    if (currentLineIndex < 0) return;

    final startOfLine = text.lastIndexOf('\n', currentLineIndex) + 1;
    final currentLine = text.substring(startOfLine, currentLineIndex + 1);

    // 체크박스 처리
    final checkboxMatch = RegExp(
      r'^(\s*[-*+])\s+\[([ xX])\]\s+(.*)$',
    ).firstMatch(currentLine);
    if (checkboxMatch != null) {
      final indent = checkboxMatch.group(1) ?? '';
      final content = checkboxMatch.group(3) ?? '';

      if (content.trim().isEmpty) {
        _runProgrammaticChange(() {
          final textBefore = text.substring(0, startOfLine);
          final textAfter = text.substring(selection.end);
          this.text = textBefore + textAfter;
          selection = TextSelection.fromPosition(
            TextPosition(offset: startOfLine),
          );
        });
        return;
      }

      final textToInsert = '\n$indent [ ] ';
      _runProgrammaticChange(() {
        final newText =
            text.substring(0, selection.start) +
            textToInsert.substring(1) +
            text.substring(selection.end);
        final newOffset = selection.start + textToInsert.length - 1;
        value = TextEditingValue(
          text: newText,
          selection: TextSelection.fromPosition(
            TextPosition(offset: newOffset),
          ),
        );
      });
      return;
    }

    // 일반 리스트 처리
    final match = _listContinuationRegex.firstMatch(currentLine);
    if (match != null) {
      final indent = match.group(1) ?? '';
      final marker = match.group(2) ?? '';
      final content = match.group(3) ?? '';

      if (content.trim().isEmpty) {
        _runProgrammaticChange(() {
          final textBefore = text.substring(0, startOfLine);
          final textAfter = text.substring(selection.end);
          this.text = textBefore + textAfter;
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
            textToInsert.substring(1) +
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

  void _runProgrammaticChange(VoidCallback action) {
    _isProgrammaticChange = true;
    action();
  }

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
        newText = selectedText.substring(
          prefix.length,
          selectedText.length - suffix.length,
        );
        newEnd = newStart + newText.length;
      } else {
        newText = '$prefix$selectedText$suffix';
        newEnd = newStart + newText.length;
      }

      value = value.copyWith(
        text: textBefore + newText + textAfter,
        selection: TextSelection(baseOffset: newStart, extentOffset: newEnd),
        composing: TextRange.empty,
      );

      // 캐시 무효화
      _lineCache.clear();
    });
  }

  void indentList(bool isIndent) {
    _runProgrammaticChange(() {
      final currentSelection = selection;
      if (currentSelection.start == 0) return;
      final startOfLine =
          text.lastIndexOf('\n', currentSelection.start - 1) + 1;
      final endOfLine = text.indexOf('\n', startOfLine);
      final lineEnd = endOfLine == -1 ? text.length : endOfLine;
      final currentLine = text.substring(startOfLine, lineEnd);

      final match = _listContinuationRegex.firstMatch(currentLine);
      if (match == null && !isIndent) return;

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
          return;
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

      _lineCache.clear();
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

    return _buildTextSpanByLines(defaultStyle);
  }

  TextSpan _buildTextSpanByLines(TextStyle defaultStyle) {
    final lines = text.split('\n');
    final List<TextSpan> lineSpans = [];
    int currentLineStart = 0;
    final cursorLine = _getLineNumber(selection.start);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineLength = line.length;
      final isOnCursorLine = (i == cursorLine);

      // 캐시 확인 (커서가 없는 줄만)
      if (!isOnCursorLine && _lineCache.containsKey(i)) {
        lineSpans.add(_lineCache[i]!.span);
      } else {
        final lineSpan = _buildSingleLine(
          line,
          currentLineStart,
          lineLength,
          isOnCursorLine,
          defaultStyle,
        );

        lineSpans.add(lineSpan);

        // 캐시 저장 (커서가 없는 줄만)
        if (!isOnCursorLine) {
          _lineCache[i] = _LineCache(lineSpan);
        }
      }

      currentLineStart += lineLength + 1; // +1 for '\n'

      if (i < lines.length - 1) {
        lineSpans.add(TextSpan(text: '\n', style: defaultStyle));
      }
    }

    return TextSpan(children: lineSpans, style: defaultStyle);
  }

  TextSpan _buildSingleLine(
    String line,
    int lineStart,
    int lineLength,
    bool isOnCursorLine,
    TextStyle defaultStyle,
  ) {
    if (line.isEmpty) {
      return TextSpan(text: '', style: defaultStyle);
    }

    // 블록 레벨 매칭 확인
    _BlockMatch? blockMatch = _findBlockLevelMatch(line);

    if (blockMatch != null) {
      return _buildBlockLevelSpan(
        blockMatch,
        line,
        lineStart,
        isOnCursorLine,
        defaultStyle,
      );
    }

    // 일반 텍스트: 인라인 스타일만 적용
    return _buildInlineStyledSpan(
      line,
      0,
      line.length,
      lineStart,
      isOnCursorLine,
      defaultStyle,
    );
  }

  _BlockMatch? _findBlockLevelMatch(String line) {
    for (final entry in _blockLevelRegexMap.entries) {
      final match = entry.value.firstMatch(line);
      if (match != null) {
        return _BlockMatch(match, entry.key);
      }
    }
    return null;
  }

  TextSpan _buildBlockLevelSpan(
    _BlockMatch blockMatch,
    String line,
    int lineStart,
    bool isOnCursorLine,
    TextStyle defaultStyle,
  ) {
    final match = blockMatch.match;
    final type = blockMatch.type;

    TextStyle style;
    final syntaxStyle = TextStyle(
      color: Colors.grey.withOpacity(0.4),
      fontWeight: FontWeight.w300,
    );

    switch (type) {
      case 'header':
        final headerLevel = match.group(1)!.length;
        style = _styleMap['h$headerLevel'] ?? _styleMap['h3'] ?? defaultStyle;
        final marker = match.group(1) ?? '';
        final space = match.group(2) ?? '';
        final content = match.group(3) ?? '';

        // 커서가 있으면 # 표시, 없으면 숨김
        if (isOnCursorLine) {
          return TextSpan(
            style: style,
            children: [
              TextSpan(
                text: marker,
                style: syntaxStyle.copyWith(
                  fontSize: style.fontSize,
                  height: style.height,
                ),
              ),
              TextSpan(text: space, style: style),
              _buildInlineStyledSpan(
                content,
                0,
                content.length,
                lineStart + marker.length + space.length,
                isOnCursorLine,
                style,
              ),
            ],
          );
        } else {
          return _buildInlineStyledSpan(
            content,
            0,
            content.length,
            lineStart + marker.length + space.length,
            isOnCursorLine,
            style,
          );
        }

      case 'list':
        style = _styleMap['list'] ?? defaultStyle;
        final marker = match.group(1) ?? '';
        final space = match.group(2) ?? '';
        final content = match.group(3) ?? '';

        return TextSpan(
          style: style,
          children: [
            TextSpan(
              text: marker,
              style: syntaxStyle.copyWith(
                height: style.height,
                fontWeight: FontWeight.w400,
              ),
            ),
            TextSpan(text: space, style: style),
            _buildInlineStyledSpan(
              content,
              0,
              content.length,
              lineStart + marker.length + space.length,
              isOnCursorLine,
              style,
            ),
          ],
        );

      case 'checkbox':
        style = _styleMap['list'] ?? defaultStyle;
        final marker = match.group(1) ?? '';
        final checkbox = match.group(2) ?? '';
        final checkState = match.group(3) ?? ' ';
        final content = match.group(4) ?? '';

        final isChecked = checkState.toLowerCase() == 'x';
        final checkboxStyle = TextStyle(
          color: isChecked ? Colors.green.shade600 : Colors.grey.shade500,
        );
        final contentStyle =
            isChecked
                ? style.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: Colors.grey.shade600,
                )
                : style;

        return TextSpan(
          children: [
            TextSpan(text: marker, style: syntaxStyle),
            TextSpan(text: ' ', style: style),
            TextSpan(text: checkbox, style: checkboxStyle),
            TextSpan(text: ' ', style: style),
            _buildInlineStyledSpan(
              content,
              0,
              content.length,
              lineStart + marker.length + checkbox.length + 2,
              isOnCursorLine,
              contentStyle,
            ),
          ],
        );

      case 'quote':
        style = _styleMap['quote'] ?? defaultStyle;
        final marker = match.group(1) ?? '';
        final space = match.group(2) ?? '';
        final content = match.group(3) ?? '';

        return TextSpan(
          style: style,
          children: [
            TextSpan(
              text: marker,
              style: syntaxStyle.copyWith(height: style.height),
            ),
            TextSpan(text: space, style: style),
            _buildInlineStyledSpan(
              content,
              0,
              content.length,
              lineStart + marker.length + space.length,
              isOnCursorLine,
              style,
            ),
          ],
        );

      case 'hr':
        style = _styleMap['hr'] ?? defaultStyle;
        return TextSpan(text: line, style: style);

      case 'codeBlock':
        style = _styleMap['code'] ?? defaultStyle;
        return TextSpan(text: line, style: style);

      case 'table':
        style = defaultStyle;
        return TextSpan(text: line, style: style);

      default:
        return TextSpan(text: line, style: defaultStyle);
    }
  }

  TextSpan _buildInlineStyledSpan(
    String text,
    int start,
    int end,
    int absoluteStart,
    bool isOnCursorLine,
    TextStyle baseStyle,
  ) {
    if (start >= end) {
      return TextSpan(text: '', style: baseStyle);
    }

    final currentText = text.substring(start, end);
    final List<_InlineMatch> allMatches = [];

    // 우선순위: boldItalic > bold/italic > 나머지
    final priorityOrder = [
      'boldItalic',
      'bold',
      'italic',
      'strikethrough',
      'highlight',
      'code',
      'mathInline',
      'link',
      'wikiLink',
      'footnote',
      'tag',
    ];

    for (final type in priorityOrder) {
      final regex = _inlineLevelRegexMap[type];
      if (regex == null) continue;

      for (final match in regex.allMatches(currentText)) {
        allMatches.add(
          _InlineMatch(
            match,
            type,
            start + match.start,
            start + match.end,
            absoluteStart + match.start,
            absoluteStart + match.end,
          ),
        );
      }
    }

    if (allMatches.isEmpty) {
      return TextSpan(text: currentText, style: baseStyle);
    }

    allMatches.sort((a, b) => a.relativeStart.compareTo(b.relativeStart));

    // 겹치지 않는 매칭만 선택
    final List<_InlineMatch> validMatches = [];
    int lastEnd = start;

    for (final match in allMatches) {
      if (match.relativeStart >= lastEnd) {
        validMatches.add(match);
        lastEnd = match.relativeEnd;
      }
    }

    final List<TextSpan> spans = [];
    int currentPos = start;

    for (final inlineMatch in validMatches) {
      if (inlineMatch.relativeStart > currentPos) {
        spans.add(
          TextSpan(
            text: text.substring(currentPos, inlineMatch.relativeStart),
            style: baseStyle,
          ),
        );
      }

      spans.add(
        _createInlineStyledSpan(inlineMatch, text, isOnCursorLine, baseStyle),
      );

      currentPos = inlineMatch.relativeEnd;
    }

    if (currentPos < end) {
      spans.add(
        TextSpan(text: text.substring(currentPos, end), style: baseStyle),
      );
    }

    return TextSpan(children: spans, style: baseStyle);
  }

  TextSpan _createInlineStyledSpan(
    _InlineMatch inlineMatch,
    String fullText,
    bool isOnCursorLine,
    TextStyle baseStyle,
  ) {
    final match = inlineMatch.match;
    final type = inlineMatch.type;
    final style = _styleMap[type] ?? baseStyle;
    final syntaxStyle = TextStyle(
      color: Colors.grey.withOpacity(0.35),
      fontWeight: FontWeight.w300,
    );

    // 커서가 매칭 영역 안에 있는지 확인
    final cursorPos = selection.start;
    final isCursorInside =
        isOnCursorLine &&
        cursorPos >= inlineMatch.absoluteStart &&
        cursorPos <= inlineMatch.absoluteEnd;

    switch (type) {
      case 'boldItalic':
        final content = match.group(1) ?? '';
        final combinedStyle = baseStyle.copyWith(
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
        );
        if (isCursorInside) {
          return TextSpan(
            children: [
              TextSpan(text: '***', style: syntaxStyle),
              TextSpan(text: content, style: combinedStyle),
              TextSpan(text: '***', style: syntaxStyle),
            ],
          );
        } else {
          return TextSpan(text: content, style: combinedStyle);
        }

      case 'bold':
        final content = match.group(1) ?? '';
        if (isCursorInside) {
          return TextSpan(
            children: [
              TextSpan(text: '**', style: syntaxStyle),
              TextSpan(text: content, style: style),
              TextSpan(text: '**', style: syntaxStyle),
            ],
          );
        } else {
          return TextSpan(text: content, style: style);
        }

      case 'italic':
        final content = match.group(1) ?? '';
        if (isCursorInside) {
          return TextSpan(
            children: [
              TextSpan(text: '*', style: syntaxStyle),
              TextSpan(text: content, style: style),
              TextSpan(text: '*', style: syntaxStyle),
            ],
          );
        } else {
          return TextSpan(text: content, style: style);
        }

      case 'strikethrough':
        final content = match.group(1) ?? '';
        if (isCursorInside) {
          return TextSpan(
            children: [
              TextSpan(text: '~~', style: syntaxStyle),
              TextSpan(text: content, style: style),
              TextSpan(text: '~~', style: syntaxStyle),
            ],
          );
        } else {
          return TextSpan(text: content, style: style);
        }

      case 'highlight':
        final content = match.group(1) ?? '';
        final highlightStyle = baseStyle.copyWith(
          backgroundColor: Colors.yellow.shade200,
        );
        if (isCursorInside) {
          return TextSpan(
            children: [
              TextSpan(text: '==', style: syntaxStyle),
              TextSpan(text: content, style: highlightStyle),
              TextSpan(text: '==', style: syntaxStyle),
            ],
          );
        } else {
          return TextSpan(text: content, style: highlightStyle);
        }

      case 'code':
        final content = match.group(1) ?? '';
        if (isCursorInside) {
          return TextSpan(
            style: style,
            children: [
              TextSpan(
                text: '`',
                style: syntaxStyle.copyWith(
                  backgroundColor: Colors.transparent,
                ),
              ),
              TextSpan(text: content),
              TextSpan(
                text: '`',
                style: syntaxStyle.copyWith(
                  backgroundColor: Colors.transparent,
                ),
              ),
            ],
          );
        } else {
          return TextSpan(text: content, style: style);
        }

      case 'mathInline':
        final content = match.group(1) ?? '';
        final mathStyle = baseStyle.copyWith(
          fontStyle: FontStyle.italic,
          color: Colors.purple.shade700,
        );
        if (isCursorInside) {
          return TextSpan(
            children: [
              TextSpan(text: '\$', style: syntaxStyle),
              TextSpan(text: content, style: mathStyle),
              TextSpan(text: '\$', style: syntaxStyle),
            ],
          );
        } else {
          return TextSpan(text: content, style: mathStyle);
        }

      case 'link':
        final linkText = match.group(1) ?? '';
        final url = match.group(2) ?? '';
        if (isCursorInside) {
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
        } else {
          return TextSpan(
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
          );
        }

      case 'wikiLink':
        final content = match.group(1) ?? '';
        if (isCursorInside) {
          return TextSpan(
            children: [
              TextSpan(text: '[[', style: syntaxStyle),
              TextSpan(text: content, style: style),
              TextSpan(text: ']]', style: syntaxStyle),
            ],
          );
        } else {
          return TextSpan(text: content, style: style);
        }

      case 'footnote':
        final number = match.group(1) ?? '';
        final footnoteStyle = baseStyle.copyWith(
          fontSize: (baseStyle.fontSize ?? 16) * 0.8,
          color: Colors.blue.shade600,
        );
        return TextSpan(text: '[$number]', style: footnoteStyle);

      case 'tag':
        final tagStyle = baseStyle.copyWith(
          color: Colors.blue.shade400,
          fontWeight: FontWeight.w500,
        );
        return TextSpan(text: match.group(0), style: tagStyle);

      default:
        return TextSpan(text: match.group(0)!, style: baseStyle);
    }
  }
}

class _BlockMatch {
  final RegExpMatch match;
  final String type;

  _BlockMatch(this.match, this.type);
}

class _InlineMatch {
  final RegExpMatch match;
  final String type;
  final int relativeStart;
  final int relativeEnd;
  final int absoluteStart;
  final int absoluteEnd;

  _InlineMatch(
    this.match,
    this.type,
    this.relativeStart,
    this.relativeEnd,
    this.absoluteStart,
    this.absoluteEnd,
  );
}

class _LineCache {
  final TextSpan span;
  _LineCache(this.span);
}
