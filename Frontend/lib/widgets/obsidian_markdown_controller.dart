// lib/widgets/obsidian_markdown_controller.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Helper classes for matching markdown syntax
class _LineMatch {
  final RegExpMatch match;
  final String type;
  _LineMatch(this.match, this.type);
  int get start => match.start;
  int get end => match.end;
}

class _InlineMatch {
  final RegExpMatch match;
  final String type;
  _InlineMatch(this.match, this.type);
  int get start => match.start;
  int get end => match.end;
}

class _StyleMatch {
  final RegExpMatch match;
  final String type;
  final bool isLineStyle;
  _StyleMatch(this.match, this.type, this.isLineStyle);
  int get start => match.start;
  int get end => match.end;
}

class ObsidianMarkdownController extends TextEditingController {
  final Map<String, TextStyle> _styleMap;

  // Pre-compiled regex for performance
  static final RegExp _headerRegex = RegExp(
    r'^(#{1,6})\s+(.*)$',
    multiLine: true,
  );
  static final RegExp _boldRegex = RegExp(r'\*\*(.*?)\*\*');
  static final RegExp _italicRegex = RegExp(r'(?<!\*)\*(?!\*)([^*]+?)\*(?!\*)');
  static final RegExp _codeRegex = RegExp(r'`([^`]+)`');
  static final RegExp _linkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  static final RegExp _listRegex = RegExp(
    r'^(\s*)([-*+]|\d+\.)\s+(.*)$',
    multiLine: true,
  );
  static final RegExp _quoteRegex = RegExp(r'^>\s+(.*)$', multiLine: true);

  ObsidianMarkdownController({
    String? text,
    required Map<String, TextStyle> styleMap,
  }) : _styleMap = styleMap,
       super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String textValue = text;
    if (textValue.isEmpty) {
      return TextSpan(text: '', style: style);
    }
    return _buildStyledTextSpan(textValue, style ?? const TextStyle(), context);
  }

  TextSpan _buildStyledTextSpan(
    String text,
    TextStyle defaultStyle,
    BuildContext context,
  ) {
    final List<TextSpan> spans = [];
    int currentIndex = 0;

    final List<_StyleMatch> allMatches = _collectAndFilterMatches(text);

    for (final _StyleMatch match in allMatches) {
      if (match.start > currentIndex) {
        spans.add(
          TextSpan(
            text: text.substring(currentIndex, match.start),
            style: defaultStyle,
          ),
        );
      }
      spans.add(_createStyledSpan(match, defaultStyle, context));
      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(
        TextSpan(text: text.substring(currentIndex), style: defaultStyle),
      );
    }

    return spans.isEmpty
        ? TextSpan(text: text, style: defaultStyle)
        : TextSpan(children: spans);
  }

  List<_StyleMatch> _collectAndFilterMatches(String text) {
    final lineMatches = [
      ..._headerRegex.allMatches(text).map((m) => _LineMatch(m, 'header')),
      ..._listRegex.allMatches(text).map((m) => _LineMatch(m, 'list')),
      ..._quoteRegex.allMatches(text).map((m) => _LineMatch(m, 'quote')),
    ];

    final inlineMatches = [
      ..._boldRegex.allMatches(text).map((m) => _InlineMatch(m, 'bold')),
      ..._italicRegex.allMatches(text).map((m) => _InlineMatch(m, 'italic')),
      ..._codeRegex.allMatches(text).map((m) => _InlineMatch(m, 'code')),
      ..._linkRegex.allMatches(text).map((m) => _InlineMatch(m, 'link')),
    ];

    final allMatches = [
      ...lineMatches.map((m) => _StyleMatch(m.match, m.type, true)),
      ...inlineMatches.map((m) => _StyleMatch(m.match, m.type, false)),
    ];

    allMatches.sort((a, b) => a.start.compareTo(b.start));

    // Filter out overlapping matches
    final List<_StyleMatch> filteredMatches = [];
    for (final current in allMatches) {
      bool hasOverlap = filteredMatches.any(
        (existing) =>
            (current.start < existing.end && current.end > existing.start),
      );
      if (!hasOverlap) {
        filteredMatches.add(current);
      }
    }
    return filteredMatches;
  }

  TextSpan _createStyledSpan(
    _StyleMatch match,
    TextStyle defaultStyle,
    BuildContext context,
  ) {
    // ... (기존 _createLineStyledSpan, _createInlineStyledSpan 메서드 내용은 여기에 통합 또는 그대로 유지)
    // 이 예제에서는 간결함을 위해 세부 구현은 생략합니다. 기존 코드를 그대로 복사해오시면 됩니다.
    if (match.isLineStyle) {
      return _createLineStyledSpan(match, defaultStyle);
    } else {
      return _createInlineStyledSpan(match, defaultStyle, context);
    }
  }

  TextSpan _createLineStyledSpan(_StyleMatch match, TextStyle defaultStyle) {
    switch (match.type) {
      case 'header':
        final headerLevel = match.match.group(1)!.length;
        final headerPrefix = match.match.group(1)!;
        final headerContent = match.match.group(2) ?? '';
        final style =
            _styleMap['h$headerLevel'] ?? _styleMap['h3'] ?? defaultStyle;
        return TextSpan(
          children: [
            TextSpan(
              text: '$headerPrefix ',
              style: style.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(text: headerContent, style: style),
          ],
        );

      case 'list':
        final indent = match.match.group(1) ?? '';
        final bullet = match.match.group(2) ?? '';
        final content = match.match.group(3) ?? '';
        return TextSpan(
          children: [
            TextSpan(text: indent, style: defaultStyle),
            TextSpan(
              text: '$bullet ',
              style: (_styleMap['list'] ?? defaultStyle).copyWith(
                color: const Color(0xFF3498db),
              ),
            ),
            TextSpan(text: content, style: defaultStyle),
          ],
        );

      case 'quote':
        final content = match.match.group(1) ?? '';
        return TextSpan(
          children: [
            TextSpan(
              text: '> ',
              style: (_styleMap['quote'] ?? defaultStyle).copyWith(
                color: Colors.grey,
              ),
            ),
            TextSpan(text: content, style: _styleMap['quote'] ?? defaultStyle),
          ],
        );

      default:
        return TextSpan(text: match.match.group(0)!, style: defaultStyle);
    }
  }

  TextSpan _createInlineStyledSpan(
    _StyleMatch match,
    TextStyle defaultStyle,
    BuildContext context,
  ) {
    switch (match.type) {
      case 'bold':
        return TextSpan(
          children: [
            TextSpan(
              text: '**',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(
              text: match.match.group(1)!,
              style: _styleMap['bold'] ?? defaultStyle,
            ),
            TextSpan(
              text: '**',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
          ],
        );

      case 'italic':
        return TextSpan(
          children: [
            TextSpan(
              text: '*',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(
              text: match.match.group(1)!,
              style: _styleMap['italic'] ?? defaultStyle,
            ),
            TextSpan(
              text: '*',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
          ],
        );

      case 'code':
        return TextSpan(
          children: [
            TextSpan(
              text: '`',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(
              text: match.match.group(1)!,
              style: _styleMap['code'] ?? defaultStyle,
            ),
            TextSpan(
              text: '`',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
          ],
        );

      case 'link':
        final linkText = match.match.group(1)!;
        final url = match.match.group(2)!;
        return TextSpan(
          text: linkText,
          style: _styleMap['link'] ?? defaultStyle,
          recognizer:
              TapGestureRecognizer()
                ..onTap = () async {
                  final uri = Uri.tryParse(url);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
        );

      default:
        return TextSpan(text: match.match.group(0)!, style: defaultStyle);
    }
  }
}
