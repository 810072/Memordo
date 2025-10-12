// lib/features/meeting_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../widgets/codemirror_editor.dart';
import '../layout/bottom_section_controller.dart';
import '../utils/ai_service.dart';
import '../utils/web_helper.dart' as web_helper;
import '../model/file_system_entry.dart';
import '../providers/file_system_provider.dart';
import '../providers/note_provider.dart';
import '../providers/tab_provider.dart';
import '../model/note_model.dart';
import '../widgets/custom_popup_menu.dart';
import '../providers/status_bar_provider.dart';

// --- ✨ [수정] Intents와 Actions 로직 변경 ---
class SaveIntent extends Intent {}

class ToggleBoldIntent extends Intent {}

class ToggleItalicIntent extends Intent {}

class IndentIntent extends Intent {}

class OutdentIntent extends Intent {}

// Action 클래스들이 이제 CodeMirrorEditorState를 직접 제어합니다.
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
  final _MeetingScreenState screenState;
  ToggleBoldAction(this.screenState);
  @override
  Object? invoke(ToggleBoldIntent intent) {
    screenState.getActiveEditor()?.toggleBold();
    return null;
  }
}

class ToggleItalicAction extends Action<ToggleItalicIntent> {
  final _MeetingScreenState screenState;
  ToggleItalicAction(this.screenState);
  @override
  Object? invoke(ToggleItalicIntent intent) {
    screenState.getActiveEditor()?.toggleItalic();
    return null;
  }
}

class IndentAction extends Action<IndentIntent> {
  final _MeetingScreenState screenState;
  IndentAction(this.screenState);
  @override
  Object? invoke(IndentIntent intent) {
    screenState.getActiveEditor()?.indent();
    return null;
  }
}

class OutdentAction extends Action<OutdentIntent> {
  final _MeetingScreenState screenState;
  OutdentAction(this.screenState);
  @override
  Object? invoke(OutdentIntent intent) {
    screenState.getActiveEditor()?.outdent();
    return null;
  }
}
// ---

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

  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  List<FileSystemEntry> _filteredFiles = [];
  Offset _suggestionBoxOffset = Offset.zero;

  // ✨ [수정] GlobalKey를 사용하여 각 탭의 에디터 인스턴스에 접근
  final Map<String, GlobalKey<CodeMirrorEditorState>> _editorKeys = {};

  // ✨ [추가] 현재 활성화된 에디터의 State를 가져오는 헬퍼 함수
  CodeMirrorEditorState? getActiveEditor() {
    final activeTabId = context.read<TabProvider>().activeTab?.id;
    if (activeTabId == null) return null;
    return _editorKeys[activeTabId]?.currentState;
  }

  @override
  void initState() {
    super.initState();
    final tabProvider = context.read<TabProvider>();
    _titleController = TextEditingController(
      text: tabProvider.activeTab?.title ?? '',
    );
    tabProvider.addListener(_onTabChange);
    context.read<NoteProvider>().addListener(_onNoteChange);

    // 초기 탭의 컨트롤러에 리스너 추가
    tabProvider.activeTab?.controller.addListener(_onTextChangedForWikiLink);

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
      _onNoteChange();
    });
  }

  @override
  void dispose() {
    context.read<TabProvider>().removeListener(_onTabChange);
    context.read<NoteProvider>().removeListener(_onNoteChange);
    Provider.of<FileSystemProvider>(
      context,
      listen: false,
    ).removeListener(_onSelectedFileChanged);
    _removeOverlay();
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  void _onTabChange() {
    final tabProvider = context.read<TabProvider>();

    // 이전에 활성화되었던 탭의 리스너를 제거
    for (var tab in tabProvider.openTabs) {
      tab.controller.removeListener(_onTextChangedForWikiLink);
    }

    final activeTab = tabProvider.activeTab;
    if (activeTab != null) {
      // 새로운 활성 탭에 리스너 추가
      activeTab.controller.addListener(_onTextChangedForWikiLink);
      if (_titleController.text != activeTab.title) {
        _titleController.text = activeTab.title;
      }
      // ✨ [추가] 탭 전환 시 에디터 키가 없으면 생성
      if (!_editorKeys.containsKey(activeTab.id)) {
        _editorKeys[activeTab.id] = GlobalKey<CodeMirrorEditorState>();
      }
    }

    if (activeTab == null && _titleController.text.isNotEmpty) {
      _titleController.clear();
    }
    _onNoteChange();
    _hideSuggestionBox();
  }

  void _onNoteChange() {
    if (!mounted) return;
    final noteProvider = context.read<NoteProvider>();
    final statusBarProvider = context.read<StatusBarProvider>();
    if (noteProvider.controller != null) {
      statusBarProvider.updateTextInfo(
        line: noteProvider.currentLine,
        char: noteProvider.currentChar,
        totalChars: noteProvider.totalChars,
      );
    } else {
      statusBarProvider.clearTextInfo();
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

  void _onTextChangedForWikiLink() {
    final controller = context.read<NoteProvider>().controller;
    if (controller == null) return;

    final text = controller.text;
    final offset = controller.selection.start;

    final wikiLinkRegex = RegExp(r'\[\[([^\]]*)');
    final matches = wikiLinkRegex.allMatches(text);

    bool foundMatch = false;
    for (final match in matches) {
      final endBracketMatch = text.indexOf(']]', match.start);
      final inBetween = endBracketMatch == -1 || offset <= endBracketMatch + 2;

      if (offset > match.start && inBetween) {
        final query = match.group(1) ?? '';
        _updateFilteredFiles(query);
        _updateSuggestionBoxPosition();
        _showSuggestionBox();
        foundMatch = true;
        break;
      }
    }

    if (!foundMatch) {
      _hideSuggestionBox();
    }
  }

  void _updateFilteredFiles(String query) {
    final allFiles = context.read<FileSystemProvider>().allMarkdownFiles;
    if (query.isEmpty) {
      _filteredFiles = allFiles;
    } else {
      _filteredFiles =
          allFiles
              .where(
                (file) => p
                    .basenameWithoutExtension(file.name)
                    .toLowerCase()
                    .contains(query.toLowerCase()),
              )
              .toList();
    }
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _showSuggestionBox() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    } else {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  void _hideSuggestionBox() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }

  void _removeOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }

  void _updateSuggestionBoxPosition() {
    final controller = context.read<NoteProvider>().controller;
    if (controller == null) return;

    final text = controller.text;
    final offset = controller.selection.start;
    final startMatch = text.lastIndexOf('[[', offset);

    if (startMatch == -1) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: controller.text,
        style: const TextStyle(
          fontSize: 16,
          height: 1.6,
          fontFamily: 'system-ui',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final caretOffset = textPainter.getOffsetForCaret(
      TextPosition(offset: startMatch),
      Rect.zero,
    );

    setState(() {
      _suggestionBoxOffset = Offset(caretOffset.dx, caretOffset.dy + 25);
    });
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder:
          (context) => Positioned(
            width: 300,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: _suggestionBoxOffset,
              child: Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(8.0),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child:
                      _filteredFiles.isEmpty
                          ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Center(child: Text('일치하는 파일 없음')),
                          )
                          : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _filteredFiles.length,
                            itemBuilder: (context, index) {
                              final file = _filteredFiles[index];
                              final fileName = p.basenameWithoutExtension(
                                file.name,
                              );
                              return ListTile(
                                dense: true,
                                title: Text(
                                  fileName,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                onTap: () {
                                  _insertWikiLink(fileName);
                                },
                              );
                            },
                          ),
                ),
              ),
            ),
          ),
    );
  }

  void _insertWikiLink(String fileName) {
    final controller = context.read<NoteProvider>().controller!;
    final text = controller.text;
    final offset = controller.selection.start;

    final startMatch = text.lastIndexOf('[[', offset);
    if (startMatch != -1) {
      final textBefore = text.substring(0, startMatch + 2);
      final textAfter = text.substring(offset);

      final newText =
          textBefore +
          fileName +
          ']]' +
          textAfter.replaceFirst(RegExp(r'[^\]]*\]?\]?'), '');

      final newOffset = startMatch + 2 + fileName.length + 2;

      controller.value = controller.value.copyWith(
        text: newText,
        selection: TextSelection.fromPosition(TextPosition(offset: newOffset)),
      );
    }
    _hideSuggestionBox();
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

    // ✨ [수정] 단축키와 액션 연결 로직 변경
    final Map<ShortcutActivator, Intent> shortcuts = {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true):
          SaveIntent(),
      const SingleActivator(LogicalKeyboardKey.keyB, control: true):
          ToggleBoldIntent(),
      const SingleActivator(LogicalKeyboardKey.keyI, control: true):
          ToggleItalicIntent(),
      const SingleActivator(LogicalKeyboardKey.tab): IndentIntent(),
      const SingleActivator(LogicalKeyboardKey.tab, shift: true):
          OutdentIntent(),
    };

    final Map<Type, Action<Intent>> actions = {
      SaveIntent: SaveAction(this),
      ToggleBoldIntent: ToggleBoldAction(this),
      ToggleItalicIntent: ToggleItalicAction(this),
      IndentIntent: IndentAction(this),
      OutdentIntent: OutdentAction(this),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              _buildNewHeader(tabProvider),
              Expanded(
                child:
                    activeTab != null
                        ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 8.0,
                          ),
                          child: _buildMarkdownEditor(activeTab),
                        )
                        : Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 8.0,
                          ),
                          child: _buildEmptyScreen(),
                        ),
              ),
            ],
          ),
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
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

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
                cursorColor: isDarkMode ? Colors.white : Colors.black,
                cursorWidth: 1.0,
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
                return InstantPopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: '더보기',
                  offset: const Offset(0, 40),
                  constraints: const BoxConstraints(
                    minWidth: 120,
                    maxWidth: 120,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    side: BorderSide(
                      color:
                          isDarkMode
                              ? Colors.grey.shade800
                              : Colors.grey.shade300,
                      width: 1.0,
                    ),
                  ),
                  elevation: 4.0,
                  color: isDarkMode ? const Color(0xFF2E2E2E) : theme.cardColor,
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
                        CompactPopupMenuItem<String>(
                          value: 'save',
                          child: Row(
                            children: [
                              Icon(
                                Icons.save_outlined,
                                size: 14,
                                color:
                                    isDarkMode
                                        ? Colors.white70
                                        : Colors.black87,
                              ),
                              const SizedBox(width: 8),
                              const Text('저장'),
                            ],
                          ),
                        ),
                        CompactPopupMenuItem<String>(
                          value: 'load',
                          child: Row(
                            children: [
                              Icon(
                                Icons.file_open_outlined,
                                size: 14,
                                color:
                                    isDarkMode
                                        ? Colors.white70
                                        : Colors.black87,
                              ),
                              const SizedBox(width: 8),
                              const Text('불러오기'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1.0),
                        CompactPopupMenuItem<String>(
                          value: 'summarize',
                          enabled:
                              activeTab != null && !bottomController.isLoading,
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_outlined,
                                size: 14,
                                color:
                                    isDarkMode
                                        ? Colors.white70
                                        : Colors.black87,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                bottomController.isLoading
                                    ? '요약 중...'
                                    : 'AI 요약 실행',
                              ),
                            ],
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
    // ✨ [수정] 탭 ID를 사용하여 에디터 키를 관리
    if (!_editorKeys.containsKey(activeTab.id)) {
      _editorKeys[activeTab.id] = GlobalKey<CodeMirrorEditorState>();
    }

    return CodeMirrorEditor(
      key: _editorKeys[activeTab.id],
      controller: activeTab.controller, // ✨ [수정] 컨트롤러 직접 전달
      onTextChanged: (text) {
        // `NoteProvider`가 컨트롤러의 리스너를 통해 변경을 감지하므로,
        // 여기서 별도로 컨트롤러 값을 설정할 필요가 없습니다.
        // `note_provider`가 상태를 업데이트합니다.
      },
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
      '$newName.md',
    );

    if (success) {
      final newPath = p.join(p.dirname(activeTab.filePath!), '$newName.md');
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
    final statusBar = context.read<StatusBarProvider>();

    // ✨ [수정] 활성 에디터에서 텍스트를 가져옴
    final editor = getActiveEditor();
    if (editor == null) {
      statusBar.showStatusMessage("에디터를 찾을 수 없습니다.", type: StatusType.error);
      return;
    }

    final content = await editor.getText();

    if (content.isEmpty) {
      statusBar.showStatusMessage("저장할 내용이 없습니다.", type: StatusType.error);
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
        statusBar.showStatusMessage(
          "저장 완료: ${p.basename(path)} ✅",
          type: StatusType.success,
        );
      } catch (e) {
        statusBar.showStatusMessage(
          "파일 저장 중 오류 발생: $e",
          type: StatusType.error,
        );
      }
    } else {
      statusBar.showStatusMessage("저장이 취소되었습니다.", type: StatusType.info);
    }
  }

  Future<void> _loadMarkdownFromFilePicker() async {
    final statusBar = context.read<StatusBarProvider>();
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'txt'],
    );
    if (result == null) {
      statusBar.showStatusMessage("파일 불러오기가 취소되었습니다.", type: StatusType.info);
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
    statusBar.showStatusMessage(
      "파일 불러오기 완료: ${p.basename(filePath ?? result.files.single.name)} ✅",
      type: StatusType.success,
    );
  }

  Future<void> _summarizeContent() async {
    final activeTab = context.read<TabProvider>().activeTab;
    final statusBar = context.read<StatusBarProvider>();
    if (activeTab == null) return;

    // ✨ [수정] 활성 에디터에서 텍스트를 가져옴
    final editor = getActiveEditor();
    if (editor == null) return;

    final content = (await editor.getText()).trim();
    if (content.length < 50) {
      statusBar.showStatusMessage(
        '요약할 내용이 너무 짧습니다 (최소 50자 필요).',
        type: StatusType.error,
      );
      return;
    }
    final bottomController = context.read<BottomSectionController>();
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
      statusBar.showStatusMessage('텍스트 요약 중 오류 발생: $e', type: StatusType.error);
    } finally {
      bottomController.setIsLoading(false);
    }
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
