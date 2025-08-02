// lib/features/meeting_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SingleActivator, LogicalKeyboardKey 사용을 위해 추가
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../widgets/obsidian_markdown_controller.dart'; // 수정된 컨트롤러 import
import '../layout/bottom_section_controller.dart';
import '../widgets/ai_summary_widget.dart';
import '../utils/ai_service.dart';
import '../utils/web_helper.dart' as web_helper;
import '../model/file_system_entry.dart';
import '../providers/file_system_provider.dart';

// --- 단축키를 위한 Intent 및 Action 클래스들 ---
class ToggleBoldIntent extends Intent {}

class ToggleItalicIntent extends Intent {}

class IndentIntent extends Intent {}

class OutdentIntent extends Intent {}

class ToggleBoldAction extends Action<ToggleBoldIntent> {
  final ObsidianMarkdownController controller;
  ToggleBoldAction(this.controller);

  @override
  Object? invoke(ToggleBoldIntent intent) {
    controller.toggleInlineSyntax('**', '**');
    return null;
  }
}

class ToggleItalicAction extends Action<ToggleItalicIntent> {
  final ObsidianMarkdownController controller;
  ToggleItalicAction(this.controller);

  @override
  Object? invoke(ToggleItalicIntent intent) {
    controller.toggleInlineSyntax('*', '*');
    return null;
  }
}

class IndentAction extends Action<IndentIntent> {
  final ObsidianMarkdownController controller;
  IndentAction(this.controller);

  @override
  Object? invoke(IndentIntent intent) {
    controller.indentList(true);
    return null;
  }
}

class OutdentAction extends Action<OutdentIntent> {
  final ObsidianMarkdownController controller;
  OutdentAction(this.controller);

  @override
  Object? invoke(OutdentIntent intent) {
    controller.indentList(false);
    return null;
  }
}
// --- Intent 및 Action 클래스 정의 끝 ---

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
  String? _currentEditingFilePath;
  String _currentEditingFileName = '새 메모';

  @override
  void initState() {
    super.initState();
    _initializeController();
    _initializeState();
  }

  void _initializeController() {
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
      'strikethrough': const TextStyle(
        decoration: TextDecoration.lineThrough,
        color: Color(0xFF6a6a6a),
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
      'list': const TextStyle(fontSize: 16, height: 1.6),
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
  }

  void _initializeState() {
    _currentEditingFilePath = widget.filePath;
    _currentEditingFileName =
        widget.filePath != null
            ? p.basenameWithoutExtension(widget.filePath!)
            : '새 메모';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fileProvider = Provider.of<FileSystemProvider>(
        context,
        listen: false,
      );
      fileProvider.scanForFileSystem();
      fileProvider.addListener(_onSelectedFileChanged);

      final bottomController = Provider.of<BottomSectionController>(
        context,
        listen: false,
      );
      bottomController.clearSummary();
      if (!bottomController.isVisible) bottomController.toggleVisibility();
    });
  }

  void _onSelectedFileChanged() {
    final fileProvider = Provider.of<FileSystemProvider>(
      context,
      listen: false,
    );
    final selectedEntry = fileProvider.selectedFileForMeetingScreen;
    if (selectedEntry != null &&
        selectedEntry.path != _currentEditingFilePath) {
      _loadMemoFromFileSystemEntry(selectedEntry);
      fileProvider.setSelectedFileForMeetingScreen(null);
    }
  }

  @override
  void dispose() {
    Provider.of<FileSystemProvider>(
      context,
      listen: false,
    ).removeListener(_onSelectedFileChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Shortcuts와 Actions를 build 메서드 내에서 정의합니다.
    final Map<ShortcutActivator, Intent> shortcuts = {
      const SingleActivator(LogicalKeyboardKey.keyB, control: true):
          ToggleBoldIntent(),
      const SingleActivator(LogicalKeyboardKey.keyI, control: true):
          ToggleItalicIntent(),
      const SingleActivator(LogicalKeyboardKey.tab): IndentIntent(),
      const SingleActivator(LogicalKeyboardKey.tab, shift: true):
          OutdentIntent(),
    };

    final Map<Type, Action<Intent>> actions = {
      ToggleBoldIntent: ToggleBoldAction(_controller),
      ToggleItalicIntent: ToggleItalicAction(_controller),
      IndentIntent: IndentAction(_controller),
      OutdentIntent: OutdentAction(_controller),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildMarkdownEditor(),
                const SizedBox(height: 24),
                _buildActionButtons(),
                const SizedBox(height: 20),
                if (context.watch<BottomSectionController>().isVisible)
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
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
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
              _createNewFolder,
              const Color(0xFF2ecc71),
            ),
            const SizedBox(width: 12),
            _buildButton(
              Icons.add_box_outlined,
              '새 메모',
              _startNewMemo,
              const Color(0xFF3498db),
            ),
          ],
        ),
      ],
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
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF2c3e50),
            height: 1.6,
            fontFamily: 'system-ui',
          ),
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration.collapsed(
            hintText: "# Start typing your markdown...\n\n**Bold text**",
            hintStyle: TextStyle(
              color: Color(0xFFbdc3c7),
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final bottomController = context.watch<BottomSectionController>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _buildButton(
              Icons.save_outlined,
              _currentEditingFilePath != null ? '저장' : '다른 이름으로 저장',
              _saveMarkdown,
              const Color(0xFF27ae60),
            ),
            const SizedBox(width: 12),
            _buildButton(
              Icons.file_upload_outlined,
              '불러오기',
              _loadMarkdownFromFilePicker,
              const Color(0xFF95a5a6),
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
    );
  }

  Widget _buildButton(
    IconData icon,
    String label,
    VoidCallback? onPressed,
    Color color, {
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
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        elevation: 2.0,
        shadowColor: color.withOpacity(0.3),
      ),
    );
  }

  // --- Logic Methods ---
  void _startNewMemo() {
    setState(() {
      _controller.clear();
      _currentEditingFilePath = null;
      _currentEditingFileName = '새 메모';
      _saveStatus = '';
    });
    context.read<BottomSectionController>().clearSummary();
    _focusNode.requestFocus();
  }

  Future<void> _createNewFolder() async {
    final fileProvider = context.read<FileSystemProvider>();
    String? folderName = await _showTextInputDialog(
      context,
      '새 폴더 생성',
      '폴더 이름을 입력하세요.',
    );
    if (folderName != null && folderName.isNotEmpty) {
      await fileProvider.createNewFolder(context, folderName);
    }
  }

  Future<void> _saveMarkdown() async {
    final content = _controller.text;
    if (content.isEmpty) {
      _showSnackBar("저장할 내용이 없습니다.", isError: true);
      return;
    }

    final fileProvider = context.read<FileSystemProvider>();

    if (kIsWeb) {
      final fileName = 'memo_${DateTime.now().toIso8601String()}.md';
      web_helper.downloadMarkdownWeb(content, fileName);
      _updateSaveStatus("파일 다운로드 완료: $fileName ✅");
      return;
    }

    String? path = _currentEditingFilePath;
    if (path == null) {
      path = await FilePicker.platform.saveFile(
        dialogTitle: '노트 저장',
        fileName: '새_메모.md',
        initialDirectory:
            fileProvider.lastSavedDirectoryPath ??
            await _getNotesDirectoryPath(),
        allowedExtensions: ['md'],
      );
    }

    if (path != null) {
      try {
        await File(path).writeAsString(content);
        fileProvider.updateLastSavedDirectoryPath(p.dirname(path));
        setState(() {
          _currentEditingFilePath = path;
          _currentEditingFileName = p.basenameWithoutExtension(path!);
          _updateSaveStatus("저장 완료: ${p.basename(path)} ✅");
        });
        fileProvider.scanForFileSystem();
      } catch (e) {
        _showSnackBar("파일 저장 중 오류 발생: $e", isError: true);
      }
    } else {
      _updateSaveStatus("저장이 취소되었습니다.");
    }
  }

  Future<void> _loadMarkdownFromFilePicker() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'txt'],
    );
    if (result == null) {
      _updateSaveStatus("파일 불러오기가 취소되었습니다.");
      return;
    }

    String content;
    String fileName;
    String? filePath;

    if (kIsWeb) {
      final fileBytes = result.files.single.bytes;
      if (fileBytes == null) return;
      content = String.fromCharCodes(fileBytes);
      fileName = result.files.single.name;
    } else {
      filePath = result.files.single.path!;
      content = await File(filePath).readAsString();
      fileName = p.basenameWithoutExtension(filePath);
      context.read<FileSystemProvider>().updateLastSavedDirectoryPath(
        p.dirname(filePath),
      );
    }
    _updateEditorContent(content, fileName, filePath);
  }

  Future<void> _loadMemoFromFileSystemEntry(FileSystemEntry entry) async {
    try {
      final content = await File(entry.path).readAsString();
      _updateEditorContent(
        content,
        p.basenameWithoutExtension(entry.name),
        entry.path,
      );
      context.read<FileSystemProvider>().updateLastSavedDirectoryPath(
        p.dirname(entry.path),
      );
    } catch (e) {
      _showSnackBar("메모 로드 중 오류 발생: $e", isError: true);
    }
  }

  Future<void> _summarizeContent() async {
    final content = _controller.text.trim();
    if (content.length < 50) {
      _showSnackBar('요약할 내용이 너무 짧습니다 (최소 50자 필요).', isError: true);
      return;
    }

    final bottomController = context.read<BottomSectionController>();
    if (!bottomController.isVisible) bottomController.toggleVisibility();

    bottomController.setIsLoading(true);
    bottomController.updateSummary('AI가 텍스트를 요약 중입니다...');

    try {
      final summary = await callBackendTask(
        taskType: "summarize",
        text: content,
      );
      bottomController.updateSummary(summary ?? '요약에 실패했거나 내용이 없습니다.');
    } catch (e) {
      bottomController.updateSummary('요약 중 오류 발생: $e');
      _showSnackBar('텍스트 요약 중 오류 발생: $e', isError: true);
    } finally {
      bottomController.setIsLoading(false);
    }
  }

  // --- Helper Methods ---
  void _updateEditorContent(String content, String fileName, String? filePath) {
    setState(() {
      _controller.text = content;
      _currentEditingFilePath = filePath;
      _currentEditingFileName = fileName;
      _updateSaveStatus("파일 불러오기 완료: $fileName ✅");
    });
  }

  void _updateSaveStatus(String status) {
    setState(() => _saveStatus = status);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  Future<String> _getNotesDirectoryPath() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('사용자 홈 디렉터리를 찾을 수 없습니다.');
    final folderPath = p.join(home, 'Documents', 'Memordo_Notes');
    final directory = Directory(folderPath);
    if (!await directory.exists()) await directory.create(recursive: true);
    return folderPath;
  }

  Future<String?> _showTextInputDialog(
    BuildContext context,
    String title,
    String hint,
  ) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(hintText: hint),
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
}
