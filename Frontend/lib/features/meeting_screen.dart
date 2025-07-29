// Frontend/lib/features/meeting_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../layout/bottom_section_controller.dart';
import '../widgets/ai_summary_widget.dart';
import '../utils/ai_service.dart';
import '../utils/web_helper.dart' as web_helper;
import 'page_type.dart';
import '../model/file_system_entry.dart';
import '../providers/file_system_provider.dart';

// ObsidianMarkdownController 클래스는 기존과 동일하게 유지됩니다.
class ObsidianMarkdownController extends TextEditingController {
  // ... (이전 코드와 동일)
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
      // _StyleMatch 타입 명시
      bool hasOverlap = filteredMatches.any(
        (existing) =>
            _overlaps(current.start, current.end, existing.start, existing.end),
      );
      if (!hasOverlap) {
        filteredMatches.add(current);
      }
    }

    for (final _StyleMatch match in filteredMatches) {
      // _StyleMatch 타입 명시
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

class MeetingScreen extends StatefulWidget {
  final String? initialText;
  final String? filePath;
  const MeetingScreen({super.key, this.initialText, this.filePath});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  late final ObsidianMarkdownController _controller;
  final FocusNode _focusNode = FocusNode();

  String _saveStatus = '';
  bool _showHintText = true;

  String? _currentEditingFilePath;
  String _currentEditingFileName = '새 메모';

  // [수정 1] Provider 인스턴스를 저장할 멤버 변수 선언
  FileSystemProvider? _fileSystemProvider;

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

    _controller = ObsidianMarkdownController(
      text: widget.initialText,
      styleMap: markdownStyles,
    );

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // [수정 2] initState에서 Provider 인스턴스를 가져와 변수에 저장하고 사용합니다.
      _fileSystemProvider = Provider.of<FileSystemProvider>(
        context,
        listen: false,
      );
      _fileSystemProvider?.scanForFileSystem();
      _fileSystemProvider?.addListener(_handleSelectedFileChange); // 리스너 추가

      final bottomController = Provider.of<BottomSectionController>(
        context,
        listen: false,
      );
      bottomController.clearSummary();
      if (!bottomController.isVisible) {
        bottomController.toggleVisibility();
      }
      if (widget.initialText != null && widget.initialText!.isNotEmpty) {
        bottomController.toggleVisibility();
      }
    });

    _currentEditingFilePath = widget.filePath;
    _currentEditingFileName =
        widget.filePath != null
            ? p.basenameWithoutExtension(widget.filePath!)
            : '새 메모';
  }

  void _handleSelectedFileChange() {
    // [수정 3] Provider.of 대신 저장된 멤버 변수(_fileSystemProvider)를 사용합니다.
    final selectedEntry = _fileSystemProvider?.selectedFileForMeetingScreen;
    if (selectedEntry != null &&
        selectedEntry.path != _currentEditingFilePath) {
      loadSelectedMemo(selectedEntry);
      _fileSystemProvider?.setSelectedFileForMeetingScreen(null);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    // [수정 4] Provider.of 대신 저장된 멤버 변수를 사용하여 안전하게 리스너를 제거합니다.
    _fileSystemProvider?.removeListener(_handleSelectedFileChange);
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

  Future<void> _saveMarkdown() async {
    final content = _controller.text;
    if (content.isEmpty) {
      if (!mounted) return;
      setState(() {
        _saveStatus = "저장할 내용이 없습니다.";
      });
      return;
    }

    final fileSystemProvider = Provider.of<FileSystemProvider>(
      context,
      listen: false,
    );

    if (_currentEditingFilePath != null && !kIsWeb) {
      try {
        final file = File(_currentEditingFilePath!);
        await file.writeAsString(content);
        if (!mounted) return;
        setState(() {
          _saveStatus = "저장 완료: ${_currentEditingFileName}.md ✅";
        });
        fileSystemProvider.scanForFileSystem();
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _saveStatus = "파일 덮어쓰기 중 오류 발생: $e ❌";
        });
        return;
      }
    }

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
            fileSystemProvider.lastSavedDirectoryPath ??
            await getOrCreateNoteFolderPath();
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
          fileSystemProvider.updateLastSavedDirectoryPath(p.dirname(filePath));

          if (!mounted) return;
          setState(() {
            _currentEditingFilePath = filePath;
            _currentEditingFileName = p.basenameWithoutExtension(filePath);
            _saveStatus = "새 파일 저장 완료: $filePath ✅";
          });
          fileSystemProvider.scanForFileSystem();
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

  Future<void> _loadMarkdown() async {
    String? content;
    String? fileName;
    String? filePath;

    final fileSystemProvider = Provider.of<FileSystemProvider>(
      context,
      listen: false,
    );

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
          fileName = p.basenameWithoutExtension(file.path);
          filePath = file.path;
          fileSystemProvider.updateLastSavedDirectoryPath(p.dirname(file.path));
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
        _currentEditingFilePath = filePath;
        _currentEditingFileName = fileName ?? '새 메모';
      });
    }
  }

  Future<void> loadSelectedMemo(FileSystemEntry entry) async {
    if (entry.isDirectory) {
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
          Provider.of<FileSystemProvider>(
            context,
            listen: false,
          ).updateLastSavedDirectoryPath(p.dirname(entry.path));
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

  void _startNewMemo() {
    if (!mounted) return;
    setState(() {
      _controller.clear();
      _currentEditingFilePath = null;
      _currentEditingFileName = '새 메모';
      _saveStatus = '';
      _showHintText = true;
      Provider.of<BottomSectionController>(
        context,
        listen: false,
      ).clearSummary();
    });
    _focusNode.requestFocus();
  }

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
    final fileSystemProvider = Provider.of<FileSystemProvider>(context);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _currentEditingFileName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2c3e50),
                  ),
                ),
                Row(
                  children: [
                    _buildButton(
                      Icons.create_new_folder_outlined,
                      '새 폴더',
                      () => fileSystemProvider.createNewFolder(context, ''),
                      const Color(0xFF2ecc71),
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
