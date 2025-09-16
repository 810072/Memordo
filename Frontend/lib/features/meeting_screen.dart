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
import '../utils/ai_service.dart';
import '../utils/web_helper.dart' as web_helper;
import '../model/file_system_entry.dart';
import '../providers/file_system_provider.dart';
import '../providers/note_provider.dart';
import '../providers/tab_provider.dart';
import '../model/note_model.dart';

// ✨ 단축키 Intent 클래스 추가
class SaveIntent extends Intent {}

class ToggleBoldIntent extends Intent {}

class ToggleItalicIntent extends Intent {}

class IndentIntent extends Intent {}

class OutdentIntent extends Intent {}

// ✨ 단축키 Action 클래스 추가
class SaveAction extends Action<SaveIntent> {
  final _MeetingScreenState screenState;
  SaveAction(this.screenState);
  @override
  Object? invoke(SaveIntent intent) {
    screenState._saveMarkdown();
    return null;
  }
}

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

class MeetingScreen extends StatefulWidget {
  final String? initialText;
  final String? filePath;
  const MeetingScreen({super.key, this.initialText, this.filePath});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  bool _isEditingTitle = false;
  late final TextEditingController _titleController;
  final FocusNode _titleFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final tabProvider = context.read<TabProvider>();
    _titleController = TextEditingController(
      text: tabProvider.activeTab?.title ?? '',
    );
    tabProvider.addListener(_onTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (tabProvider.openTabs.isEmpty) {
        tabProvider.openNewTab(
          filePath: widget.filePath,
          content: widget.initialText,
        );
      }
      final fileProvider = Provider.of<FileSystemProvider>(
        context,
        listen: false,
      );
      fileProvider.addListener(_onSelectedFileChanged);
    });
  }

  void _onTabChange() {
    final tabProvider = context.read<TabProvider>();
    final activeTab = tabProvider.activeTab;
    if (activeTab != null && _titleController.text != activeTab.title) {
      _titleController.text = activeTab.title;
    }
    if (activeTab == null && _titleController.text.isNotEmpty) {
      _titleController.clear();
    }
  }

  void _onSelectedFileChanged() async {
    final fileProvider = Provider.of<FileSystemProvider>(
      context,
      listen: false,
    );
    final selectedEntry = fileProvider.selectedFileForMeetingScreen;
    if (selectedEntry != null) {
      final content = await File(selectedEntry.path).readAsString();
      context.read<TabProvider>().openNewTab(
        filePath: selectedEntry.path,
        content: content,
      );
      fileProvider.setSelectedFileForMeetingScreen(null);
    }
  }

  @override
  void dispose() {
    context.read<TabProvider>().removeListener(_onTabChange);
    Provider.of<FileSystemProvider>(
      context,
      listen: false,
    ).removeListener(_onSelectedFileChanged);
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  Map<String, TextStyle> _getMarkdownStyles(bool isDarkMode) {
    final Color h1Color = isDarkMode ? Colors.white : const Color(0xFF1a1a1a);
    final Color h2Color = isDarkMode ? Colors.white : const Color(0xFF2a2a2a);
    final Color h3Color = isDarkMode ? Colors.white : const Color(0xFF3a3a3a);
    final Color boldColor = isDarkMode ? Colors.white : const Color(0xFF1a1a1a);
    final Color italicColor =
        isDarkMode ? Colors.white : const Color(0xFF2a2a2a);
    final Color strikeColor =
        isDarkMode ? Colors.grey.shade500 : const Color(0xFF6a6a6a);
    final Color quoteColor =
        isDarkMode ? Colors.grey.shade400 : const Color(0xFF7f8c8d);
    final Color codeBgColor =
        isDarkMode ? Colors.grey.shade800 : const Color(0xFFF5F5F5);

    return {
      'h1': TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: h1Color,
        height: 1.3,
      ),
      'h2': TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: h2Color,
        height: 1.3,
      ),
      'h3': TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: h3Color,
        height: 1.3,
      ),
      'bold': TextStyle(fontWeight: FontWeight.bold, color: boldColor),
      'italic': TextStyle(fontStyle: FontStyle.italic, color: italicColor),
      'strikethrough': TextStyle(
        decoration: TextDecoration.lineThrough,
        color: strikeColor,
      ),
      'code': TextStyle(
        fontFamily: 'monospace',
        backgroundColor: codeBgColor,
        color: const Color(0xFFe74c3c),
        fontSize: 14,
      ),
      'link': const TextStyle(
        color: Color(0xFF3498db),
        decoration: TextDecoration.underline,
      ),
      'list': const TextStyle(fontSize: 16, height: 1.6),
      'quote': TextStyle(
        color: quoteColor,
        fontStyle: FontStyle.italic,
        fontSize: 16,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tabProvider = context.watch<TabProvider>();
    final activeTab = tabProvider.activeTab;

    if (activeTab != null) {
      Provider.of<NoteProvider>(
        context,
        listen: false,
      ).register(activeTab.controller, activeTab.focusNode);
    }

    // ✨ 단축키 맵에 저장(Ctrl+S) 추가
    final Map<ShortcutActivator, Intent> shortcuts =
        activeTab != null
            ? {
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  SaveIntent(),
              const SingleActivator(LogicalKeyboardKey.keyB, control: true):
                  ToggleBoldIntent(),
              const SingleActivator(LogicalKeyboardKey.keyI, control: true):
                  ToggleItalicIntent(),
              const SingleActivator(LogicalKeyboardKey.tab): IndentIntent(),
              const SingleActivator(LogicalKeyboardKey.tab, shift: true):
                  OutdentIntent(),
            }
            : {};

    // ✨ 액션 맵에 저장 액션 추가
    final Map<Type, Action<Intent>> actions =
        activeTab != null
            ? {
              SaveIntent: SaveAction(this),
              ToggleBoldIntent: ToggleBoldAction(
                activeTab.controller as ObsidianMarkdownController,
              ),
              ToggleItalicIntent: ToggleItalicAction(
                activeTab.controller as ObsidianMarkdownController,
              ),
              IndentIntent: IndentAction(
                activeTab.controller as ObsidianMarkdownController,
              ),
              OutdentIntent: OutdentAction(
                activeTab.controller as ObsidianMarkdownController,
              ),
            }
            : {};

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Column(
          children: [
            _buildNewHeader(tabProvider),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 8.0,
                ),
                child:
                    activeTab != null
                        ? _buildMarkdownEditor(activeTab)
                        : _buildEmptyScreen(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.note_add_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            '열려있는 메모가 없습니다.',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('새 메모 작성'),
            onPressed: () => context.read<TabProvider>().openNewTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildNewHeader(TabProvider tabProvider) {
    final activeTab = tabProvider.activeTab;
    return Container(
      height: 45,
      padding: const EdgeInsets.only(left: 20.0, right: 8.0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          _isEditingTitle && activeTab != null
              ? TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                autofocus: true,
                textAlign: TextAlign.center,
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
                onTap:
                    activeTab == null
                        ? null
                        : () {
                          setState(() {
                            _isEditingTitle = true;
                          });
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _titleFocusNode.requestFocus(),
                          );
                        },
                borderRadius: BorderRadius.circular(8.0),
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    activeTab?.title ?? '메모',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          Align(
            alignment: Alignment.centerRight,
            child: Consumer<BottomSectionController>(
              builder: (context, bottomController, child) {
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: '더보기',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  constraints: const BoxConstraints(maxWidth: 180.0),
                  elevation: 4.0,
                  color: Theme.of(context).cardColor,
                  onSelected: (value) {
                    switch (value) {
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
                          enabled: activeTab != null,
                          child: ListTile(
                            leading: Icon(
                              bottomController.isLoading
                                  ? Icons.hourglass_empty
                                  : Icons.auto_awesome_outlined,
                            ),
                            title: Text(
                              bottomController.isLoading
                                  ? '요약 중...'
                                  : 'AI 요약 실행',
                            ),
                          ),
                        ),
                      ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownEditor(NoteTab activeTab) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final markdownStyles = _getMarkdownStyles(isDarkMode);

    (activeTab.controller as ObsidianMarkdownController).updateStyles(
      markdownStyles,
    );

    return TextField(
      controller: activeTab.controller,
      focusNode: activeTab.focusNode,
      style: TextStyle(
        fontSize: 16,
        color: isDarkMode ? Colors.white : const Color(0xFF2c3e50),
        height: 1.6,
        fontFamily: 'system-ui',
      ),
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration.collapsed(
        hintText: "메모를 시작하세요...",
        hintStyle: TextStyle(
          color: Color(0xFFbdc3c7),
          fontSize: 15,
          height: 1.6,
        ),
      ),
    );
  }

  Future<void> _renameCurrentFile(String newName) async {
    final tabProvider = context.read<TabProvider>();
    final activeTab = tabProvider.activeTab;
    if (activeTab == null || newName.isEmpty || newName == activeTab.title) {
      _titleController.text = activeTab?.title ?? '';
      return;
    }
    if (activeTab.filePath == null) {
      activeTab.title = newName;
      _titleController.text = newName;
      tabProvider.notifyListeners();
      return;
    }

    final fileProvider = context.read<FileSystemProvider>();
    final entry = FileSystemEntry(
      name: p.basename(activeTab.filePath!),
      path: activeTab.filePath!,
      isDirectory: false,
    );
    final success = await fileProvider.renameEntry(
      context,
      entry,
      newName + '.md',
    );

    if (success) {
      final newPath = p.join(p.dirname(activeTab.filePath!), newName + '.md');
      tabProvider.updateTabInfo(tabProvider.activeTabIndex, newPath);
      _titleController.text = newName;
    } else {
      _titleController.text = activeTab.title;
    }
  }

  Future<void> _saveMarkdown() async {
    final tabProvider = context.read<TabProvider>();
    final activeTab = tabProvider.activeTab;
    if (activeTab == null) return;

    final content = activeTab.controller.text;
    if (content.isEmpty) {
      _showSnackBar("저장할 내용이 없습니다.", isError: true);
      return;
    }
    final fileProvider = context.read<FileSystemProvider>();
    if (kIsWeb) {
      final fileName = '${activeTab.title}.md';
      web_helper.downloadMarkdownWeb(content, fileName);
      return;
    }
    String? path = activeTab.filePath;
    if (path == null) {
      path = await FilePicker.platform.saveFile(
        dialogTitle: '노트 저장',
        fileName: '${activeTab.title}.md',
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

        tabProvider.updateTabInfo(tabProvider.activeTabIndex, path);

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
    String? filePath;
    if (kIsWeb) {
      final fileBytes = result.files.single.bytes;
      if (fileBytes == null) return;
      content = String.fromCharCodes(fileBytes);
    } else {
      filePath = result.files.single.path!;
      content = await File(filePath).readAsString();
      context.read<FileSystemProvider>().updateLastSavedDirectoryPath(
        p.dirname(filePath),
      );
    }

    context.read<TabProvider>().openNewTab(
      filePath: filePath,
      content: content,
    );
    _showSnackBar(
      "파일 불러오기 완료: ${p.basename(filePath ?? result.files.single.name)} ✅",
    );
  }

  Future<void> _summarizeContent() async {
    final activeTab = context.read<TabProvider>().activeTab;
    if (activeTab == null) return;

    final content = activeTab.controller.text.trim();
    if (content.length < 50) {
      _showSnackBar('요약할 내용이 너무 짧습니다 (최소 50자 필요).', isError: true);
      return;
    }
    final bottomController = context.read<BottomSectionController>();
    bottomController.setIsLoading(true);
    bottomController.updateSummary('AI가 텍스트를 요약 중입니다...');
    bottomController.setActiveTab(2);
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
