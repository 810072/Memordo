// lib/features/meeting_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart'; // ✅ provider 임포트 확인
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../layout/bottom_section_controller.dart';
import '../layout/main_layout.dart';
import '../layout/right_sidebar_content.dart';
import '../widgets/ai_summary_widget.dart';
import '../utils/ai_service.dart';
import '../utils/web_helper.dart' as web_helper;
import 'page_type.dart';
import '../model/file_system_entry.dart'; // ✅ 단계 1: 이 줄을 추가합니다.

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

    final List<_LineMatch> lineMatches = [];

    for (final match in _headerRegex.allMatches(text)) {
      lineMatches.add(_LineMatch(match, 'header'));
    }

    for (final match in _listRegex.allMatches(text)) {
      lineMatches.add(_LineMatch(match, 'list'));
    }

    for (final match in _quoteRegex.allMatches(text)) {
      lineMatches.add(_LineMatch(match, 'quote'));
    }

    final List<_InlineMatch> inlineMatches = [];

    for (final match in _boldRegex.allMatches(text)) {
      inlineMatches.add(_InlineMatch(match, 'bold'));
    }

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

    for (final match in _codeRegex.allMatches(text)) {
      inlineMatches.add(_InlineMatch(match, 'code'));
    }

    for (final match in _linkRegex.allMatches(text)) {
      inlineMatches.add(_InlineMatch(match, 'link'));
    }

    // `allMatches` 및 `filteredMatches` 리스트의 타입을 명시적으로 지정하여 `Object?` 오류 방지
    final List<_StyleMatch> allMatches = [
      ...lineMatches.map((m) => _StyleMatch(m.match, m.type, true)),
      ...inlineMatches.map((m) => _StyleMatch(m.match, m.type, false)),
    ];

    allMatches.sort((a, b) => a.start.compareTo(b.start));

    final List<_StyleMatch> filteredMatches = [];
    for (final _StyleMatch current in allMatches) {
      // ✅ _StyleMatch 타입 명시
      bool hasOverlap = filteredMatches.any(
        (existing) =>
            _overlaps(current.start, current.end, existing.start, existing.end),
      );
      if (!hasOverlap) {
        filteredMatches.add(current);
      }
    }

    for (final _StyleMatch match in filteredMatches) {
      // ✅ _StyleMatch 타입 명시
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

  bool _overlaps(int start1, int end1, int start2, int end2) {
    return start1 < end2 && end1 > start2;
  }

  TextSpan _createStyledSpan(
    _StyleMatch match,
    TextStyle defaultStyle,
    BuildContext context,
  ) {
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

// ✅ 중복 선언 제거: _LineMatch, _InlineMatch, _StyleMatch 클래스 정의는 파일 하단에 한 번만 존재해야 합니다.
// 만약 이 파일의 상단이나 중간에 이미 이 클래스들이 정의되어 있었다면, 해당 중복 정의를 삭제하고
// 아래 정의만 남겨두세요.

// LocalMemo 클래스는 FileSystemEntry로 대체되므로, 여기서는 삭제하거나 사용하지 않습니다.
// class LocalMemo {
//   final String fileName;
//   final String filePath;
//   LocalMemo({required this.fileName, required this.filePath});
// }

class MeetingScreen extends StatefulWidget {
  final String? initialText; // Add this parameter
  final String? filePath; // ✅ 파일 경로를 저장할 필드 추가
  const MeetingScreen({
    super.key,
    this.initialText,
    this.filePath,
  }); // ✅ 생성자에 포함 // Modify constructor

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  late final ObsidianMarkdownController _controller;
  final FocusNode _focusNode = FocusNode();

  String _saveStatus = '';
  String? _lastSavedDirectoryPath;
  // List<LocalMemo> _savedMemosList = []; // ✅ 단계 2: 이 줄을 삭제하거나 주석 처리합니다.
  // bool _isLoadingMemos = false; // ✅ 단계 2: 이 줄을 삭제하거나 주석 처리합니다.
  List<FileSystemEntry> _fileSystemEntries = []; // ✅ 단계 2: 이 줄을 추가합니다.
  bool _isLoadingFileSystem = false; // ✅ 단계 2: 이 줄을 추가합니다.

  // 힌트 텍스트를 보여줄지 여부
  bool _showHintText = true;

  // ✅ 추가: 현재 편집 중인 파일의 경로를 저장
  String? _currentEditingFilePath;
  // ✅ 추가: 현재 편집 중인 파일의 이름을 저장 (UI 표시용)
  String _currentEditingFileName = '새 메모';

  @override
  void initState() {
    super.initState();

    final Map<String, TextStyle> markdownStyles = {
      'h1': const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1a1a1a),
        height: 1.3,
      ),
      'h2': const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2a2a2a),
        height: 1.3,
      ),
      'h3': const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Color(0xFF3a3a3a),
        height: 1.3,
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

    // Initialize controller with initialText if provided
    _controller = ObsidianMarkdownController(
      text: widget.initialText,
      styleMap: markdownStyles,
    );

    // Adjust hint text visibility based on initialText
    _showHintText = widget.initialText?.isEmpty ?? true;

    _controller.addListener(() {
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

    _scanForFileSystem(); // ✅ 단계 2: 새로운 파일 시스템 스캔 함수를 호출합니다.

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bottomController = Provider.of<BottomSectionController>(
        // ✅ Provider.of 사용 확인
        context,
        listen: false,
      );
      bottomController.clearSummary();
      bottomController.toggleVisibility();
      // If initialText is provided, hide the bottom section for summary
      if (widget.initialText != null && widget.initialText!.isNotEmpty) {
        bottomController.toggleVisibility(); // Hide if it was visible
      }
    });

    _currentEditingFilePath = widget.filePath; // ✅ 전달된 경로를 내부 상태로 저장
    _currentEditingFileName =
        widget.filePath != null
            ? p.basenameWithoutExtension(widget.filePath!)
            : '새 메모';
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

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
      if (!mounted) return;
      setState(() {
        _saveStatus = "저장할 내용이 없습니다.";
      });
      return;
    }

    // ✅ 수정: _currentEditingFilePath가 있으면 해당 경로에 바로 저장
    if (_currentEditingFilePath != null && !kIsWeb) {
      try {
        final file = File(_currentEditingFilePath!);
        await file.writeAsString(content);
        if (!mounted) return;
        setState(() {
          _saveStatus = "저장 완료: ${_currentEditingFileName}.md ✅";
        });
        _scanForFileSystem(); // ✅ 단계 2: 새로운 파일 시스템 스캔 함수를 호출합니다.
        return; // 현재 파일에 저장했으므로 함수 종료
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _saveStatus = "파일 덮어쓰기 중 오류 발생: $e ❌";
        });
        return;
      }
    }

    // _currentEditingFilePath가 없거나 웹 환경인 경우 새로운 파일로 저장
    if (kIsWeb) {
      final fileName =
          '새_노트_${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}_${DateTime.now().hour}${DateTime.now().minute}${DateTime.now().second}.md';
      web_helper.downloadMarkdownWeb(content, fileName);
      if (!mounted) return;
      setState(() {
        _saveStatus = "파일 다운로드 완료: $fileName ✅";
      });
    } else {
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

          // ✅ 새로 저장된 파일 경로와 이름을 현재 편집 파일로 설정
          if (!mounted) return;
          setState(() {
            _currentEditingFilePath = filePath;
            _currentEditingFileName = p.basenameWithoutExtension(filePath);
            _saveStatus = "새 파일 저장 완료: $filePath ✅";
          });
          _scanForFileSystem(); // ✅ 단계 2: 새로운 파일 시스템 스캔 함수를 호출합니다.
        } else {
          if (!mounted) return;
          setState(() {
            _saveStatus = "파일 저장이 취소되었습니다.";
          });
        }
      } catch (e) {
        if (!mounted) return;
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
    String? filePath; // ✅ 파일 경로도 함께 저장

    if (kIsWeb) {
      try {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['md', 'txt'],
          allowMultiple: false,
        );
        if (!mounted) return;

        if (result != null && result.files.single.bytes != null) {
          content = String.fromCharCodes(result.files.single.bytes!);
          fileName = result.files.single.name;
          // 웹에서는 실제 파일 경로가 없으므로 null 또는 임시값
          filePath = null;
        } else {
          if (!mounted) return;
          setState(() {
            _saveStatus = "파일 불러오기가 취소되었습니다.";
          });
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _saveStatus = "파일 불러오기 오류: $e ❌";
        });
        return;
      }
    } else {
      try {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['md', 'txt'],
        );
        if (!mounted) return;

        if (result != null && result.files.single.path != null) {
          File file = File(result.files.single.path!);
          content = await file.readAsString();
          fileName = p.basenameWithoutExtension(file.path); // 확장자 없는 이름
          filePath = file.path; // ✅ 파일 경로 저장
          _lastSavedDirectoryPath = p.dirname(file.path);
        } else {
          if (!mounted) return;
          setState(() {
            _saveStatus = "파일 불러오기가 취소되었습니다.";
          });
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _saveStatus = "파일 불러오기 오류: $e ❌";
        });
        return;
      }
    }
    if (mounted) {
      setState(() {
        _controller.text = content ?? '';
        _saveStatus = "파일 불러오기 완료: ${fileName ?? '알 수 없는 파일'} ✅";
        _showHintText = content?.isEmpty ?? true;
        // ✅ 불러온 파일 정보 저장
        _currentEditingFilePath = filePath;
        _currentEditingFileName = fileName ?? '새 메모';
      });
    }
  }

  // ✅ 단계 2: 새로운 파일 시스템 스캔 함수를 추가합니다.
  Future<void> _scanForFileSystem() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _isLoadingFileSystem = false;
        _fileSystemEntries = []; // 웹 환경에서는 로컬 파일 시스템에 접근할 수 없습니다.
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingFileSystem = true; // 스캔 시작 시 로딩 상태 true
      _fileSystemEntries = []; // 기존 목록 초기화
    });

    try {
      final notesDirPath =
          await getOrCreateNoteFolderPath(); // 'Memordo_Notes' 폴더 경로 가져오기
      final rootDirectory = Directory(notesDirPath);
      if (await rootDirectory.exists()) {
        final List<FileSystemEntry> entries = [];
        // 재귀 함수를 호출하여 파일 시스템 구조를 빌드합니다.
        await _buildDirectoryTree(rootDirectory, entries);

        // 항목들을 정렬합니다 (폴더 먼저, 그 다음 파일, 알파벳 순).
        _sortEntries(entries);

        if (mounted) {
          setState(() {
            _fileSystemEntries = entries; // 스캔 완료 후 목록 업데이트
          });
        }
      }
    } catch (e) {
      debugPrint('파일 시스템 스캔 오류: $e');
      if (!mounted) return;
      setState(() {
        _saveStatus = "파일 시스템 스캔 중 오류 발생: $e ❌";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFileSystem = false; // 스캔 완료(성공/실패 무관) 시 로딩 상태 false
        });
      }
    }
  }

  // ✅ 단계 2: 재귀적으로 디렉토리를 탐색하고 FileSystemEntry를 빌드하는 헬퍼 함수를 추가합니다.
  Future<void> _buildDirectoryTree(
    Directory directory,
    List<FileSystemEntry> parentChildren,
  ) async {
    // 디렉토리 내의 모든 항목(파일 및 하위 디렉토리)을 가져옵니다.
    final List<FileSystemEntity> entities = directory.listSync();
    List<FileSystemEntry> currentDirChildren = [];

    for (var entity in entities) {
      final name = p.basename(entity.path); // 파일/폴더의 이름
      if (entity is Directory) {
        final List<FileSystemEntry> dirChildren = [];
        await _buildDirectoryTree(entity, dirChildren); // 폴더인 경우 재귀적으로 탐색
        currentDirChildren.add(
          FileSystemEntry(
            name: name,
            path: entity.path,
            isDirectory: true,
            children: dirChildren,
          ),
        );
      } else if (entity is File &&
          p.extension(entity.path).toLowerCase() == '.md') {
        // .md 파일인 경우에만 추가합니다. (다른 파일 형식은 무시)
        currentDirChildren.add(
          FileSystemEntry(name: name, path: entity.path, isDirectory: false),
        );
      }
    }
    _sortEntries(currentDirChildren); // 현재 레벨의 항목들 정렬
    parentChildren.addAll(currentDirChildren); // 부모의 자식 목록에 추가
  }

  // ✅ 단계 2: 파일 시스템 항목 정렬 헬퍼 함수를 추가합니다.
  void _sortEntries(List<FileSystemEntry> entries) {
    entries.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1; // 폴더가 파일보다 먼저 오도록 정렬
      if (!a.isDirectory && b.isDirectory) return 1; // 파일이 폴더보다 나중에 오도록 정렬
      return a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ); // 같은 타입이면 이름순(알파벳) 정렬
    });
  }

  // ✅ 단계 2: FileSystemEntry 객체를 인자로 받도록 _loadSelectedMemo 함수를 변경합니다.
  Future<void> _loadSelectedMemo(FileSystemEntry entry) async {
    if (entry.isDirectory) {
      // 폴더는 로드하지 않고, 클릭 시 확장/축소 로직을 UI에서 처리하도록 둡니다.
      debugPrint('폴더는 로드할 수 없습니다: ${entry.name}');
      return;
    }
    try {
      final file = File(entry.path);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (mounted) {
          setState(() {
            _controller.text = content;
            _saveStatus =
                "파일 불러오기 완료: ${p.basenameWithoutExtension(entry.name)} ✅";
            _showHintText = content.isEmpty;
            _currentEditingFilePath = entry.path;
            _currentEditingFileName = p.basenameWithoutExtension(entry.name);
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _saveStatus = "선택된 메모 파일이 존재하지 않습니다. ❌";
        });
      }
    } catch (e) {
      debugPrint('메모 로드 오류: $e');
      if (!mounted) return;
      setState(() {
        _saveStatus = "메모 로드 중 오류 발생: $e ❌";
      });
    }
  }

  // ✅ 추가: 새 메모 시작
  void _startNewMemo() {
    if (!mounted) return;
    setState(() {
      _controller.clear(); // 텍스트 필드 내용 지우기
      _currentEditingFilePath = null; // 현재 파일 경로 초기화
      _currentEditingFileName = '새 메모'; // 파일 이름 "새 메모"로 변경
      _saveStatus = ''; // 저장 상태 메시지 지우기
      _showHintText = true; // 힌트 텍스트 다시 표시
      Provider.of<BottomSectionController>(
        context,
        listen: false,
      ).clearSummary(); // AI 요약 지우기
    });
    _focusNode.requestFocus(); // 텍스트 필드에 포커스 주기
  }

  // ✅ 단계 4: 새 폴더 생성 함수를 추가합니다.
  Future<void> _createNewFolder() async {
    if (kIsWeb) {
      _showSnackBar('웹 환경에서는 폴더를 생성할 수 없습니다.', isError: true);
      return;
    }
    // 사용자에게 새 폴더 이름 입력받기
    String? folderName = await _showTextInputDialog(
      context,
      '새 폴더 생성',
      '폴더 이름을 입력하세요.',
    );
    if (folderName == null || folderName.trim().isEmpty) return;

    try {
      // 현재 편집 중인 파일의 폴더 또는 기본 노트 폴더를 부모 경로로 사용
      String parentPath =
          _currentEditingFilePath != null
              ? p.dirname(_currentEditingFilePath!)
              : await getOrCreateNoteFolderPath();

      final newFolderPath = p.join(parentPath, folderName);
      final newDirectory = Directory(newFolderPath);

      if (await newDirectory.exists()) {
        _showSnackBar('이미 같은 이름의 폴더가 존재합니다. ❌', isError: true);
        return;
      }

      await newDirectory.create(
        recursive: false,
      ); // 하위 폴더까지 재귀적으로 생성할 필요가 없다면 false
      _showSnackBar('폴더 생성 완료: $folderName ✅');
      _scanForFileSystem(); // 파일 시스템 다시 스캔하여 UI 업데이트
    } catch (e) {
      _showSnackBar('폴더 생성 중 오류 발생: $e ❌', isError: true);
    }
  }

  // ✅ 단계 4: 파일/폴더 이름 변경 함수를 추가합니다.
  Future<void> _renameEntry(FileSystemEntry entry) async {
    if (kIsWeb) {
      _showSnackBar('웹 환경에서는 파일/폴더 이름을 변경할 수 없습니다.', isError: true);
      return;
    }
    String? newName = await _showTextInputDialog(
      context,
      '이름 변경',
      '새 이름을 입력하세요.',
      initialValue: entry.name,
    );
    if (newName == null || newName.trim().isEmpty || newName == entry.name) {
      return;
    }

    try {
      String newPath = p.join(p.dirname(entry.path), newName);
      // 새 이름으로 이미 항목이 존재하는지 확인
      if (await FileSystemEntity.type(newPath) !=
          FileSystemEntityType.notFound) {
        _showSnackBar('이미 같은 이름의 파일/폴더가 존재합니다. ❌', isError: true);
        return;
      }

      if (entry.isDirectory) {
        await Directory(entry.path).rename(newPath);
      } else {
        await File(entry.path).rename(newPath);
        // 현재 편집 중인 파일이면 경로 및 이름 업데이트
        if (_currentEditingFilePath == entry.path) {
          setState(() {
            _currentEditingFilePath = newPath;
            _currentEditingFileName = p.basenameWithoutExtension(newPath);
          });
        }
      }
      _showSnackBar('이름 변경 완료: ${entry.name} -> $newName ✅');
      _scanForFileSystem(); // 파일 시스템 다시 스캔하여 UI 업데이트
    } catch (e) {
      _showSnackBar('이름 변경 중 오류 발생: $e ❌', isError: true);
    }
  }

  // ✅ 단계 4: 파일/폴더 삭제 함수를 추가합니다.
  Future<void> _deleteEntry(FileSystemEntry entry) async {
    if (kIsWeb) {
      _showSnackBar('웹 환경에서는 파일/폴더를 삭제할 수 없습니다.', isError: true);
      return;
    }
    // 사용자에게 삭제 확인 다이얼로그 표시
    bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('삭제 확인'),
            content: Text('${entry.name}을(를) 정말 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
    if (confirm != true) return; // 사용자가 취소했으면 중단

    try {
      if (entry.isDirectory) {
        await Directory(entry.path).delete(recursive: true); // 폴더와 그 내용까지 모두 삭제
      } else {
        await File(entry.path).delete();
        // 현재 편집 중인 파일이면 에디터 초기화
        if (_currentEditingFilePath == entry.path) {
          _startNewMemo(); // 새 메모 시작 (현재 편집 중이던 파일 삭제 시)
        }
      }
      _showSnackBar('삭제 완료: ${entry.name} ✅');
      _scanForFileSystem(); // 파일 시스템 다시 스캔하여 UI 업데이트
    } catch (e) {
      _showSnackBar('삭제 중 오류 발생: $e ❌', isError: true);
    }
  }

  // ✅ 단계 4: 사용자 입력 다이얼로그 헬퍼 함수를 추가합니다.
  Future<String?> _showTextInputDialog(
    BuildContext context,
    String title,
    String hintText, {
    String? initialValue,
  }) async {
    TextEditingController controller = TextEditingController(
      text: initialValue,
    );
    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(hintText: hintText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('확인'),
              ),
            ],
          ),
    );
  }

  // AI 요약 기능 (기존 AI Summarize 버튼 onPressed 수정)
  Future<void> _summarizeContent() async {
    final bottomController = Provider.of<BottomSectionController>(
      context,
      listen: false,
    );

    if (bottomController.isLoading) {
      return;
    }

    final content = _controller.text.trim();
    if (content.isEmpty || content.length < 50) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('요약할 내용이 너무 짧거나 없습니다 (최소 50자 필요).'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (!bottomController.isVisible) {
      bottomController.toggleVisibility();
    }

    bottomController.setIsLoading(true);
    bottomController.updateSummary('AI가 텍스트를 요약 중입니다...');

    try {
      final String? summary = await callBackendTask(
        taskType: "summarize",
        text: content,
      );

      if (!mounted) return;

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
      if (!mounted) return;
      bottomController.updateSummary('요약 중 오류 발생: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('텍스트 요약 중 오류가 발생했습니다: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        bottomController.setIsLoading(false);
      }
    }
  }

  // ✅ 단계 4: SnackBar 헬퍼 함수에 isError 인자 추가
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        margin: const EdgeInsets.all(16.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomController = Provider.of<BottomSectionController>(context);

    return MainLayout(
      activePage: PageType.home,
      rightSidebarChild:
          kIsWeb
              ? null
              : RightSidebarContent(
                isLoading: _isLoadingFileSystem,
                fileSystemEntries: _fileSystemEntries,
                onEntryTap: (entry) => _loadSelectedMemo(entry),
                onRefresh: _scanForFileSystem,
                // ✅ 단계 4: 파일 조작 함수들을 RightSidebarContent에 전달합니다.
                // RightSidebarContent에서 이 함수들을 ContextMenu 등으로 호출할 수 있습니다.
                onRenameEntry: _renameEntry, // 추가
                onDeleteEntry: _deleteEntry, // 추가
              ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ✅ 현재 편집 중인 파일 이름 표시
                  Text(
                    _currentEditingFileName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2c3e50),
                    ),
                  ),
                  Row(
                    // ✅ 단계 4: 버튼들을 그룹화합니다.
                    children: [
                      _buildButton(
                        Icons.create_new_folder_outlined, // 새 폴더 아이콘
                        '새 폴더',
                        _createNewFolder, // ✅ 단계 4: 새 폴더 생성 함수
                        const Color(0xFF2ecc71), // 새 폴더 버튼 색상 (예: 녹색)
                        fgColor: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      _buildButton(
                        Icons.add_box_outlined,
                        '새 메모',
                        _startNewMemo,
                        const Color(0xFF3498db),
                        fgColor: Colors.white,
                      ),
                    ],
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
                        // ✅ 버튼 텍스트 변경: 파일 경로가 있으면 '저장' 없으면 '다른 이름으로 저장'
                        _currentEditingFilePath != null && !kIsWeb
                            ? '저장'
                            : '다른 이름으로 저장',
                        _saveMarkdown,
                        const Color(0xFF27ae60),
                      ),
                      const SizedBox(width: 12),
                      _buildButton(
                        Icons.file_upload_outlined,
                        '불러오기',
                        _loadMarkdown,
                        const Color(0xFF95a5a6),
                        fgColor: Colors.white,
                      ),
                    ],
                  ),
                  _buildButton(
                    Icons.auto_awesome_outlined,
                    bottomController.isLoading ? '요약 중...' : 'AI 요약',
                    bottomController.isLoading ? null : _summarizeContent,
                    const Color(0xFFf39c12),
                    isLoading: bottomController.isLoading,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (bottomController.isVisible) const AiSummaryWidget(),
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
                        : null,
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
    bool isLoading = false,
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

// ✅ 중복 선언 제거: _LineMatch, _InlineMatch, _StyleMatch 클래스 정의는 파일 하단에 한 번만 존재해야 합니다.
// 이 정의만 남기고, 만약 파일의 다른 위치에 이 클래스들의 중복 정의가 있다면 모두 삭제해주세요.
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
