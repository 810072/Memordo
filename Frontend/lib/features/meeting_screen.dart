// lib/features/meeting_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../widgets/obsidian_markdown_controller.dart';
import '../layout/bottom_section_controller.dart';
import '../widgets/ai_summary_widget.dart';
import '../utils/ai_service.dart';
import '../utils/web_helper.dart' as web_helper;
import '../model/file_system_entry.dart';
import '../providers/file_system_provider.dart';

// --- 단축키 Intent 및 Action 클래스 (기존과 동일) ---
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

  bool _isEditingTitle = false;
  late final TextEditingController _titleController;
  final FocusNode _titleFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initializeController();
    _initializeState();
    _titleController = TextEditingController(text: _currentEditingFileName);
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
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        child: Column(
          children: [
            _buildNewHeader(),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 8.0,
                ),
                child: _buildMarkdownEditor(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewHeader() {
    // ✨ [수정] 헤더를 고정 높이 40px의 Container로 감싸서 정렬을 맞춥니다.
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child:
                _isEditingTitle
                    ? TextField(
                      controller: _titleController,
                      focusNode: _titleFocusNode,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(bottom: 2),
                      ),
                      onSubmitted: (newName) {
                        _renameCurrentFile(newName.trim());
                        setState(() {
                          _isEditingTitle = false;
                        });
                      },
                      onTapOutside: (_) {
                        _renameCurrentFile(_titleController.text.trim());
                        setState(() {
                          _isEditingTitle = false;
                        });
                      },
                    )
                    : InkWell(
                      onTap: () {
                        setState(() {
                          _isEditingTitle = true;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _titleFocusNode.requestFocus();
                        });
                      },
                      borderRadius: BorderRadius.circular(8.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _currentEditingFileName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
          ),
          Consumer<BottomSectionController>(
            builder: (context, bottomController, child) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: '더보기',
                onSelected: (value) {
                  switch (value) {
                    case 'new_memo':
                      _startNewMemo();
                      break;
                    case 'save':
                      _saveMarkdown();
                      break;
                    case 'load':
                      _loadMarkdownFromFilePicker();
                      break;
                    case 'summarize':
                      _summarizeContent();
                      break;
                  }
                },
                itemBuilder:
                    (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'new_memo',
                        child: ListTile(
                          leading: Icon(Icons.add_box_outlined),
                          title: Text('새 메모'),
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'save',
                        child: ListTile(
                          leading: Icon(Icons.save_outlined),
                          title: Text('저장'),
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'load',
                        child: ListTile(
                          leading: Icon(Icons.file_upload_outlined),
                          title: Text('불러오기'),
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'summarize',
                        child: ListTile(
                          leading: Icon(
                            bottomController.isLoading
                                ? Icons.hourglass_empty
                                : Icons.auto_awesome_outlined,
                          ),
                          title: Text(
                            bottomController.isLoading ? '요약 중...' : 'AI 요약 실행',
                          ),
                        ),
                      ),
                    ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownEditor() {
    return TextField(
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
        hintText: "# 마크다운으로 메모를 시작하세요...\n\n**굵은 텍스트**",
        hintStyle: TextStyle(
          color: Color(0xFFbdc3c7),
          fontSize: 15,
          height: 1.6,
        ),
      ),
    );
  }

  // --- 로직 메서드 ---

  Future<void> _renameCurrentFile(String newName) async {
    if (newName.isEmpty || newName == _currentEditingFileName) {
      _titleController.text = _currentEditingFileName;
      return;
    }

    if (_currentEditingFilePath == null) {
      setState(() {
        _currentEditingFileName = newName;
        _titleController.text = newName;
      });
      return;
    }

    final fileProvider = context.read<FileSystemProvider>();
    final entry = FileSystemEntry(
      name: p.basename(_currentEditingFilePath!),
      path: _currentEditingFilePath!,
      isDirectory: false,
    );

    final success = await fileProvider.renameEntry(
      context,
      entry,
      newName + '.md',
    );

    if (success) {
      setState(() {
        _currentEditingFileName = newName;
        _currentEditingFilePath = p.join(
          p.dirname(_currentEditingFilePath!),
          newName + '.md',
        );
        _titleController.text = newName;
      });
    } else {
      _titleController.text = _currentEditingFileName;
    }
  }

  void _startNewMemo() {
    setState(() {
      _controller.clear();
      _currentEditingFilePath = null;
      _currentEditingFileName = '새 메모';
      _saveStatus = '';
      _titleController.text = '새 메모';
    });
    context.read<BottomSectionController>().setActiveTab(0);
    context.read<BottomSectionController>().clearSummary();
    _focusNode.requestFocus();
  }

  Future<void> _saveMarkdown() async {
    final content = _controller.text;
    if (content.isEmpty) {
      _showSnackBar("저장할 내용이 없습니다.", isError: true);
      return;
    }

    final fileProvider = context.read<FileSystemProvider>();

    if (kIsWeb) {
      final fileName = '$_currentEditingFileName.md';
      web_helper.downloadMarkdownWeb(content, fileName);
      _updateSaveStatus("파일 다운로드 완료: $fileName ✅");
      return;
    }

    String? path = _currentEditingFilePath;
    if (path == null) {
      path = await FilePicker.platform.saveFile(
        dialogTitle: '노트 저장',
        fileName: '$_currentEditingFileName.md',
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
          _titleController.text = _currentEditingFileName;
        });
        fileProvider.scanForFileSystem();
        _showSnackBar("저장 완료: ${p.basename(path)} ✅");
      } catch (e) {
        _showSnackBar("파일 저장 중 오류 발생: $e", isError: true);
      }
    } else {
      _showSnackBar("저장이 취소되었습니다.");
    }
  }

  Future<void> _loadMarkdownFromFilePicker() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'txt'],
    );
    if (result == null) {
      _showSnackBar("파일 불러오기가 취소되었습니다.");
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

    bottomController.setIsLoading(true);
    bottomController.updateSummary('AI가 텍스트를 요약 중입니다...');
    bottomController.setActiveTab(1);

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
      _titleController.text = fileName;
    });
    _showSnackBar("파일 불러오기 완료: $fileName ✅");
    context.read<BottomSectionController>().setActiveTab(0);
    context.read<BottomSectionController>().clearSummary();
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
}
