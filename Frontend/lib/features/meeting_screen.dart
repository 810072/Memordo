// lib/features/meeting_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart'; // Provider 임포트 유지
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../layout/bottom_section_controller.dart';
import '../layout/main_layout.dart';
import '../layout/right_sidebar_content.dart';
import '../widgets/ai_summary_widget.dart';
import '../utils/ai_service.dart'; // AI 서비스 호출을 위해 추가
import '../utils/web_helper.dart' as web_helper; // 웹 전용 헬퍼 함수를 위해 추가
import 'page_type.dart';

// 옵시디언 스타일 마크다운 에디터 컨트롤러 (커서 위치 수정 버전)
class ObsidianMarkdownController extends TextEditingController {
  final Map<String, TextStyle> _styleMap;

  // 정규식을 미리 컴파일해서 성능 최적화
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
    required BuildContext context, // context를 받아서 하위 함수로 전달
    TextStyle? style,
    required bool withComposing,
  }) {
    final String textValue = text;
    if (textValue.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    return _buildStyledTextSpan(
      textValue,
      style ?? const TextStyle(),
      context,
    ); // context 전달
  }

  TextSpan _buildStyledTextSpan(
    String text,
    TextStyle defaultStyle,
    BuildContext context,
  ) {
    // context 추가
    final List<TextSpan> spans = [];
    int currentIndex = 0;

    // 모든 라인별 패턴 매치 수집
    final List<_LineMatch> lineMatches = [];

    // 헤더 매치
    for (final match in _headerRegex.allMatches(text)) {
      lineMatches.add(_LineMatch(match, 'header'));
    }

    // 리스트 매치
    for (final match in _listRegex.allMatches(text)) {
      lineMatches.add(_LineMatch(match, 'list'));
    }

    // 인용문 매치
    for (final match in _quoteRegex.allMatches(text)) {
      lineMatches.add(_LineMatch(match, 'quote'));
    }

    // 모든 인라인 스타일 매치 수집
    final List<_InlineMatch> inlineMatches = [];

    // 볼드
    for (final match in _boldRegex.allMatches(text)) {
      inlineMatches.add(_InlineMatch(match, 'bold'));
    }

    // 이탤릭 (볼드와 겹치지 않는 것만)
    for (final match in _italicRegex.allMatches(text)) {
      bool overlapsWithBold = inlineMatches.any(
        (m) =>
            m.type == 'bold' &&
            _overlaps(match.start, match.end, m.start, m.end),
      );
      if (!overlapsWithBold) {
        inlineMatches.add(_InlineMatch(match, 'italic'));
      }
    }

    // 코드
    for (final match in _codeRegex.allMatches(text)) {
      inlineMatches.add(_InlineMatch(match, 'code'));
    }

    // 링크
    for (final match in _linkRegex.allMatches(text)) {
      inlineMatches.add(_InlineMatch(match, 'link'));
    }

    // 모든 매치를 시작 위치 순으로 정렬
    final List<_StyleMatch> allMatches = [
      ...lineMatches.map((m) => _StyleMatch(m.match, m.type, true)),
      ...inlineMatches.map((m) => _StyleMatch(m.match, m.type, false)),
    ];

    allMatches.sort((a, b) => a.start.compareTo(b.start));

    // 중복 제거 (먼저 나오는 매치 우선, 라인 스타일이 인라인보다 우선)
    final List<_StyleMatch> filteredMatches = [];
    for (final current in allMatches) {
      bool hasOverlap = filteredMatches.any(
        (existing) =>
            _overlaps(current.start, current.end, existing.start, existing.end),
      );
      if (!hasOverlap) {
        filteredMatches.add(current);
      }
    }

    // TextSpan 생성 - 원본 텍스트의 모든 문자를 순서대로 처리
    for (final match in filteredMatches) {
      // 매치 이전의 일반 텍스트 추가
      if (match.start > currentIndex) {
        spans.add(
          TextSpan(
            text: text.substring(currentIndex, match.start),
            style: defaultStyle,
          ),
        );
      }

      // 스타일이 적용된 텍스트 추가
      spans.add(_createStyledSpan(match, defaultStyle, context)); // context 전달
      currentIndex = match.end;
    }

    // 남은 텍스트 추가
    if (currentIndex < text.length) {
      spans.add(
        TextSpan(text: text.substring(currentIndex), style: defaultStyle),
      );
    }

    return spans.isEmpty
        ? TextSpan(text: text, style: defaultStyle)
        : TextSpan(children: spans);
  }

  bool _overlaps(int start1, int end1, int start2, int end2) {
    return start1 < end2 && end1 > start2;
  }

  TextSpan _createStyledSpan(
    _StyleMatch match,
    TextStyle defaultStyle,
    BuildContext context,
  ) {
    // context 추가
    if (match.isLineStyle) {
      return _createLineStyledSpan(match, defaultStyle);
    } else {
      return _createInlineStyledSpan(
        match,
        defaultStyle,
        context,
      ); // context 전달
    }
  }

  TextSpan _createLineStyledSpan(_StyleMatch match, TextStyle defaultStyle) {
    // final String fullText = match.match.group(0)!; // 사용되지 않아 주석 처리

    switch (match.type) {
      case 'header':
        final headerLevel = match.match.group(1)!.length;
        final headerPrefix = match.match.group(1)!;
        final headerContent = match.match.group(2) ?? '';

        TextStyle headerStyle;
        switch (headerLevel) {
          case 1:
            headerStyle = _styleMap['h1'] ?? defaultStyle;
            break;
          case 2:
            headerStyle = _styleMap['h2'] ?? defaultStyle;
            break;
          case 3:
            headerStyle = _styleMap['h3'] ?? defaultStyle;
            break;
          default:
            headerStyle = _styleMap['h3'] ?? defaultStyle;
        }

        return TextSpan(
          children: [
            TextSpan(
              text: headerPrefix + ' ',
              style: headerStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(text: headerContent, style: headerStyle),
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
              text: bullet + ' ',
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
    // context 추가
    switch (match.type) {
      case 'bold':
        final content = match.match.group(1)!;
        return TextSpan(
          children: [
            TextSpan(
              text: '**',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(text: content, style: _styleMap['bold'] ?? defaultStyle),
            TextSpan(
              text: '**',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
          ],
        );

      case 'italic':
        final content = match.match.group(1)!;
        return TextSpan(
          children: [
            TextSpan(
              text: '*',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(text: content, style: _styleMap['italic'] ?? defaultStyle),
            TextSpan(
              text: '*',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
          ],
        );

      case 'code':
        final content = match.match.group(1)!;
        return TextSpan(
          children: [
            TextSpan(
              text: '`',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(text: content, style: _styleMap['code'] ?? defaultStyle),
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
          children: [
            TextSpan(
              text: '[',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(
              text: linkText,
              style: _styleMap['link'] ?? defaultStyle,
              recognizer:
                  TapGestureRecognizer()
                    ..onTap = () async {
                      final uri = Uri.tryParse(url);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      } else {
                        // context를 통해 SnackBar 표시
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('유효하지 않은 링크입니다: $url')),
                        );
                      }
                    },
            ),
            TextSpan(
              text: '](',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
            TextSpan(
              text: url,
              style: defaultStyle.copyWith(
                color: Colors.grey.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: ')',
              style: defaultStyle.copyWith(color: Colors.grey.withOpacity(0.6)),
            ),
          ],
        );

      default:
        return TextSpan(text: match.match.group(0)!, style: defaultStyle);
    }
  }
}

// 헬퍼 클래스들
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

class LocalMemo {
  final String fileName;
  final String filePath;
  LocalMemo({required this.fileName, required this.filePath});
}

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  late final ObsidianMarkdownController _controller;
  final FocusNode _focusNode = FocusNode();

  String _saveStatus = '';
  String? _lastSavedDirectoryPath;
  List<LocalMemo> _savedMemosList = [];
  bool _isLoadingMemos = false;

  // 힌트 텍스트를 보여줄지 여부
  bool _showHintText = true;

  @override
  void initState() {
    super.initState();

    // 마크다운 스타일 정의
    final Map<String, TextStyle> markdownStyles = {
      'h1': const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1a1a1a),
        height: 1.2,
      ),
      'h2': const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2a2a2a),
        height: 1.2,
      ),
      'h3': const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Color(0xFF3a3a3a),
        height: 1.2,
      ),
      'bold': const TextStyle(
        fontWeight: FontWeight.bold,
        color: Color(0xFF1a1a1a),
      ),
      'italic': const TextStyle(
        fontStyle: FontStyle.italic,
        color: Color(0xFF2a2a2a),
      ),
      'code': const TextStyle(
        fontFamily: 'monospace',
        backgroundColor: Color(0xFFF5F5F5),
        color: Color(0xFFe74c3c),
        fontSize: 14,
      ),
      'link': const TextStyle(
        color: Color(0xFF3498db),
        decoration: TextDecoration.underline,
      ),
      'list': const TextStyle(
        fontWeight: FontWeight.bold,
        color: Color(0xFF3498db),
      ),
      'quote': const TextStyle(
        color: Color(0xFF7f8c8d),
        fontStyle: FontStyle.italic,
        fontSize: 16,
      ),
    };

    _controller = ObsidianMarkdownController(styleMap: markdownStyles);

    // 텍스트 변경 감지 리스너 (ValueListenableBuilder 사용으로 setState 호출은 더 이상 필요 없음)
    _controller.addListener(() {
      // 힌트 텍스트 가시성 제어
      if (_controller.text.isEmpty && !_showHintText) {
        setState(() {
          _showHintText = true;
        });
      } else if (_controller.text.isNotEmpty && _showHintText) {
        setState(() {
          _showHintText = false;
        });
      }
    });

    _scanForMemos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bottomController = Provider.of<BottomSectionController>(
        context,
        listen: false,
      );
      bottomController.clearSummary();
      bottomController.toggleVisibility(); // 초기에는 숨김 (AI 요약 영역)
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // 데스크톱 환경에서만 노트 폴더 경로를 가져옵니다.
  Future<String> getOrCreateNoteFolderPath() async {
    if (kIsWeb) {
      throw UnsupportedError('웹 환경에서는 로컬 파일 시스템에 접근할 수 없습니다.');
    }
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('사용자 홈 디렉터리를 찾을 수 없습니다.');
    final folderPath =
        Platform.isMacOS
            ? p.join(home, 'Memordo_Notes')
            : p.join(home, 'Documents', 'Memordo_Notes');
    final directory = Directory(folderPath);
    if (!await directory.exists()) await directory.create(recursive: true);
    return folderPath;
  }

  // 마크다운 저장 함수
  Future<void> _saveMarkdown() async {
    final content = _controller.text;
    if (content.isEmpty) {
      if (!mounted) return; // mounted check
      setState(() {
        _saveStatus = "저장할 내용이 없습니다.";
      });
      return;
    }

    if (kIsWeb) {
      // 웹 환경에서는 다운로드 방식으로 저장
      final fileName =
          '새_노트_${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}_${DateTime.now().hour}${DateTime.now().minute}${DateTime.now().second}.md';
      web_helper.downloadMarkdownWeb(content, fileName);
      if (!mounted) return; // mounted check
      setState(() {
        _saveStatus = "파일 다운로드 완료: $fileName ✅";
      });
    } else {
      // 데스크톱 환경에서는 파일 피커로 저장
      try {
        String? initialDirectory =
            _lastSavedDirectoryPath ?? await getOrCreateNoteFolderPath();
        String? filePath = await FilePicker.platform.saveFile(
          dialogTitle: '노트 저장',
          fileName:
              '새_노트_${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}.md',
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: ['md'],
        );
        if (filePath != null) {
          final file = File(filePath);
          await file.writeAsString(content);
          _lastSavedDirectoryPath = p.dirname(filePath);
          if (!mounted) return; // mounted check
          setState(() {
            _saveStatus = "저장 완료: $filePath ✅";
          });
          _scanForMemos(); // 저장 후 목록 새로고침
        } else {
          if (!mounted) return; // mounted check
          setState(() {
            _saveStatus = "파일 저장이 취소되었습니다.";
          });
        }
      } catch (e) {
        if (!mounted) return; // mounted check
        setState(() {
          _saveStatus = "파일 저장 중 오류 발생: $e ❌";
        });
      }
    }
  }

  // 마크다운 불러오기 함수
  Future<void> _loadMarkdown() async {
    String? content;
    String? fileName;
    if (kIsWeb) {
      // 웹 환경에서는 파일 선택기로 불러오기
      try {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['md', 'txt'],
          allowMultiple: false,
        );
        if (!mounted) return; // PickFiles 이후 mounted 체크

        if (result != null && result.files.single.bytes != null) {
          content = String.fromCharCodes(result.files.single.bytes!);
          fileName = result.files.single.name;
        } else {
          if (!mounted) return; // mounted check
          setState(() {
            _saveStatus = "파일 불러오기가 취소되었습니다.";
          });
          return;
        }
      } catch (e) {
        if (!mounted) return; // mounted check
        setState(() {
          _saveStatus = "파일 불러오기 오류: $e ❌";
        });
        return;
      }
    } else {
      // 데스크톱 환경에서는 파일 피커로 불러오기
      try {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['md', 'txt'],
        );
        if (!mounted) return; // PickFiles 이후 mounted 체크

        if (result != null && result.files.single.path != null) {
          File file = File(result.files.single.path!);
          content = await file.readAsString();
          fileName = p.basename(file.path);
          _lastSavedDirectoryPath = p.dirname(file.path);
        } else {
          if (!mounted) return; // mounted check
          setState(() {
            _saveStatus = "파일 불러오기가 취소되었습니다.";
          });
          return;
        }
      } catch (e) {
        if (!mounted) return; // mounted check
        setState(() {
          _saveStatus = "파일 불러오기 오류: $e ❌";
        });
        return;
      }
    }
    if (mounted) {
      // mounted 체크
      setState(() {
        _controller.text = content ?? ''; // String? -> String
        _saveStatus = "파일 불러오기 완료: ${fileName ?? '알 수 없는 파일'} ✅";
        _showHintText = content?.isEmpty ?? true; // String?의 isEmpty 접근
      });
    }
  }

  // 로컬 메모 스캔 (웹 환경에서는 동작하지 않음)
  Future<void> _scanForMemos() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _isLoadingMemos = false; // 웹에서는 스캔하지 않으므로 로딩 해제
        _savedMemosList = [];
      });
      return;
    }
    if (!mounted) return; // mounted check
    setState(() {
      _isLoadingMemos = true;
      _savedMemosList = [];
    });
    try {
      final notesDir = await getOrCreateNoteFolderPath();
      final directory = Directory(notesDir);
      if (await directory.exists()) {
        final List<LocalMemo> memos = [];
        await for (var entity in directory.list()) {
          if (entity is File &&
              p.extension(entity.path).toLowerCase() == '.md') {
            memos.add(
              LocalMemo(
                fileName: p.basenameWithoutExtension(entity.path),
                filePath: entity.path,
              ),
            );
          }
        }
        if (mounted) {
          // mounted check
          memos.sort((a, b) => a.fileName.compareTo(b.fileName));
          setState(() {
            _savedMemosList = memos;
          });
        }
      }
    } catch (e) {
      debugPrint('메모 스캔 오류: $e');
      if (!mounted) return; // mounted check
      setState(() {
        _saveStatus = "메모 스캔 중 오류 발생: $e ❌";
      });
    } finally {
      if (mounted) {
        // mounted check
        setState(() {
          _isLoadingMemos = false;
        });
      }
    }
  }

  // 선택된 메모 로드
  Future<void> _loadSelectedMemo(LocalMemo memo) async {
    try {
      final file = File(memo.filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (mounted) {
          // mounted check
          setState(() {
            _controller.text = content;
            _saveStatus = "파일 불러오기 완료: ${memo.fileName}.md ✅";
            _showHintText = content.isEmpty; // 불러온 내용이 없으면 힌트 표시
          });
        }
      } else {
        if (!mounted) return; // mounted check
        setState(() {
          _saveStatus = "선택된 메모 파일이 존재하지 않습니다. ❌";
        });
      }
    } catch (e) {
      debugPrint('메모 로드 오류: $e');
      if (!mounted) return; // mounted check
      setState(() {
        _saveStatus = "메모 로드 중 오류 발생: $e ❌";
      });
    }
  }

  // AI 요약 기능 (기존 AI Summarize 버튼 onPressed 수정)
  Future<void> _summarizeContent() async {
    final bottomController = Provider.of<BottomSectionController>(
      // Provider.of 사용
      context,
      listen: false,
    );

    if (bottomController.isLoading) {
      // 이미 요약 중
      return;
    }

    final content = _controller.text.trim();
    if (content.isEmpty || content.length < 50) {
      // 너무 짧은 내용은 요약하지 않음
      if (!mounted) return; // mounted check
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('요약할 내용이 너무 짧거나 없습니다 (최소 50자 필요).'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    // AI 요약 영역을 보이도록 토글
    if (!bottomController.isVisible) {
      bottomController.toggleVisibility();
    }

    bottomController.setIsLoading(true);
    bottomController.updateSummary('AI가 텍스트를 요약 중입니다...');

    try {
      final String? summary = await callBackendTask(
        taskType: "summarize", // AI 서비스의 요약 작업 유형
        text: content,
      );

      if (!mounted) return; // mounted check

      if (summary != null && summary.isNotEmpty) {
        bottomController.updateSummary(summary);
      } else {
        bottomController.updateSummary('요약에 실패했거나 내용이 없습니다.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('텍스트 요약에 실패했습니다.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return; // mounted check
      bottomController.updateSummary('요약 중 오류 발생: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('텍스트 요약 중 오류가 발생했습니다: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        // mounted check
        bottomController.setIsLoading(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // AiSummaryController 대신 BottomSectionController를 사용
    final bottomController = Provider.of<BottomSectionController>(
      context,
    ); // Provider.of 사용

    return MainLayout(
      activePage: PageType.home,
      rightSidebarChild:
          kIsWeb
              ? null // 웹에서는 로컬 파일 스캔을 지원하지 않으므로 사이드바 숨김
              : RightSidebarContent(
                isLoading: _isLoadingMemos,
                memos: _savedMemosList,
                onMemoTap: (memo) => _loadSelectedMemo(memo),
                onRefresh: _scanForMemos,
              ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Markdown Editor",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2c3e50),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildMarkdownEditor(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _buildButton(
                        Icons.save_outlined,
                        'Save',
                        _saveMarkdown,
                        const Color(0xFF27ae60),
                      ),
                      const SizedBox(width: 12),
                      _buildButton(
                        Icons.file_upload_outlined,
                        'Load',
                        _loadMarkdown,
                        const Color(0xFF95a5a6),
                        fgColor: Colors.white,
                      ),
                    ],
                  ),
                  _buildButton(
                    Icons.auto_awesome_outlined,
                    bottomController.isLoading
                        ? '요약 중...'
                        : 'AI Summarize', // 텍스트 변경
                    bottomController.isLoading
                        ? null
                        : _summarizeContent, // 실제 AI 요약 함수 연결
                    const Color(0xFFf39c12),
                    isLoading: bottomController.isLoading, // 로딩 상태 전달
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // AI 요약 위젯의 가시성은 BottomSectionController에서 관리
              if (bottomController.isVisible) // isVisible 상태에 따라 표시
                const AiSummaryWidget(),
              const SizedBox(height: 20),
              Text(
                _saveStatus,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdownEditor() {
    return Container(
      height: 500,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: const Color(0xFFe1e8ed), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, child) {
            return TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF2c3e50),
                height: 1.6,
                fontFamily: 'system-ui',
              ),
              cursorColor: const Color(0xFF3498db),
              cursorWidth: 2,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText:
                    _showHintText
                        ? "# Start typing your markdown...\n\n**Bold text**\n*Italic text*\n`inline code`\n\n- List item\n- Another item\n\n> Quote text\n\n[Link](https://example.com)"
                        : null, // _showHintText 상태에 따라 힌트 텍스트 표시
                hintStyle: const TextStyle(
                  color: Color(0xFFbdc3c7),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildButton(
    IconData icon,
    String label,
    VoidCallback? onPressed,
    Color bgColor, {
    Color fgColor = Colors.white,
    bool isLoading = false, // 로딩 상태 추가
  }) {
    return ElevatedButton.icon(
      icon:
          isLoading
              ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
              : Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        elevation: 2.0,
        shadowColor: bgColor.withOpacity(0.3),
      ),
    );
  }
}
