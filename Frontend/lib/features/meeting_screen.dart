// lib/features/meeting_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../widgets/markdown_controller.dart';
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

// --- Intents and Actions for Shortcuts ---
class SaveIntent extends Intent {}

class ToggleBoldIntent extends Intent {}

class ToggleItalicIntent extends Intent {}

class IndentIntent extends Intent {}

class OutdentIntent extends Intent {}

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
  final MarkdownController controller;
  ToggleBoldAction(this.controller);
  @override
  Object? invoke(ToggleBoldIntent intent) {
    controller.toggleInlineSyntax('**', '**');
    return null;
  }
}

class ToggleItalicAction extends Action<ToggleItalicIntent> {
  final MarkdownController controller;
  ToggleItalicAction(this.controller);
  @override
  Object? invoke(ToggleItalicIntent intent) {
    controller.toggleInlineSyntax('*', '*');
    return null;
  }
}

class IndentAction extends Action<IndentIntent> {
  final MarkdownController controller;
  IndentAction(this.controller);
  @override
  Object? invoke(IndentIntent intent) {
    controller.indentList(true);
    return null;
  }
}

class OutdentAction extends Action<OutdentIntent> {
  final MarkdownController controller;
  OutdentAction(this.controller);
  @override
  Object? invoke(OutdentIntent intent) {
    controller.indentList(false);
    return null;
  }
}

// --- Main Widget ---
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

  // 위키링크 추천 UI 상태 변수
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  List<FileSystemEntry> _filteredFiles = [];
  Offset _suggestionBoxOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    final tabProvider = context.read<TabProvider>();
    _titleController = TextEditingController(
      text: tabProvider.activeTab?.title ?? '',
    );
    tabProvider.addListener(_onTabChange);
    context.read<NoteProvider>().addListener(_onNoteChange);

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

    if (tabProvider.openTabs.isNotEmpty) {
      for (var tab in tabProvider.openTabs) {
        tab.controller.removeListener(_onTextChangedForWikiLink);
      }
    }

    final activeTab = tabProvider.activeTab;
    if (activeTab != null) {
      activeTab.controller.addListener(_onTextChangedForWikiLink);
      if (_titleController.text != activeTab.title) {
        _titleController.text = activeTab.title;
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

  // ✨ 개선된 스타일 맵 - 더 많은 기능 지원
  // ✨ 옵시디언 스타일 마크다운 스타일 맵
  Map<String, TextStyle> _getMarkdownStyles(bool isDarkMode) {
    final Color textColor =
        isDarkMode ? const Color(0xFFDCDCDC) : const Color(0xFF2c3e50);
    final Color h1Color =
        isDarkMode ? const Color(0xFFFFFFFF) : const Color(0xFF1a1a1a);
    final Color h2Color =
        isDarkMode ? const Color(0xFFF0F0F0) : const Color(0xFF2a2a2a);
    final Color h3Color =
        isDarkMode ? const Color(0xFFE8E8E8) : const Color(0xFF3a3a3a);
    final Color quoteColor =
        isDarkMode ? const Color(0xFF9E9E9E) : const Color(0xFF7f8c8d);
    final Color codeBgColor =
        isDarkMode ? const Color(0x1AFFFFFF) : const Color(0xFFF5F5F5);
    final Color codeTextColor =
        isDarkMode ? const Color(0xFFE06C75) : const Color(0xFFe74c3c);

    return {
      // 헤더 스타일
      'h1': TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: h1Color,
        height: 1.4,
        letterSpacing: -0.5,
      ),
      'h2': TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: h2Color,
        height: 1.4,
        letterSpacing: -0.3,
      ),
      'h3': TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: h3Color,
        height: 1.4,
      ),
      'h4': TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: h3Color,
        height: 1.4,
      ),
      'h5': TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: h3Color,
        height: 1.4,
      ),
      'h6': TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: h3Color,
        height: 1.4,
      ),

      // 인라인 스타일
      'bold': TextStyle(fontWeight: FontWeight.w700, color: textColor),
      'italic': TextStyle(fontStyle: FontStyle.italic, color: textColor),
      'boldItalic': TextStyle(
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
        color: textColor,
      ),
      'strikethrough': TextStyle(
        decoration: TextDecoration.lineThrough,
        decorationColor:
            isDarkMode ? const Color(0xFF888888) : const Color(0xFF999999),
        decorationThickness: 2.0,
        color: isDarkMode ? const Color(0xFF888888) : const Color(0xFF999999),
      ),
      'highlight': TextStyle(
        backgroundColor:
            isDarkMode
                ? const Color(0x40FFEB3B)
                : const Color(0xFFFFEB3B).withOpacity(0.4),
        color: textColor,
      ),
      'code': TextStyle(
        fontFamily: 'Consolas, Monaco, Courier New, monospace',
        backgroundColor: codeBgColor,
        color: codeTextColor,
        fontSize: 14,
        letterSpacing: 0.2,
      ),

      // 링크 스타일
      'link': TextStyle(
        color: isDarkMode ? const Color(0xFF61AFEF) : const Color(0xFF3498db),
        decoration: TextDecoration.underline,
        decorationColor:
            isDarkMode
                ? const Color(0xFF61AFEF).withOpacity(0.5)
                : const Color(0xFF3498db).withOpacity(0.5),
      ),
      'wikiLink': TextStyle(
        color: isDarkMode ? const Color(0xFF98C379) : const Color(0xFF27ae60),
        decoration: TextDecoration.none,
        fontWeight: FontWeight.w500,
      ),

      // 리스트 및 인용구
      'list': TextStyle(fontSize: 16, color: textColor, height: 1.7),
      'quote': TextStyle(
        color: quoteColor,
        fontStyle: FontStyle.italic,
        fontSize: 16,
        height: 1.6,
      ),

      // 기타
      'hr': TextStyle(
        color: isDarkMode ? const Color(0xFF404040) : const Color(0xFFE0E0E0),
        letterSpacing: 2,
      ),
      'image': TextStyle(
        color: isDarkMode ? const Color(0xFF61AFEF) : const Color(0xFF3498db),
        fontStyle: FontStyle.italic,
      ),
      'tag': TextStyle(
        color: isDarkMode ? const Color(0xFFC678DD) : const Color(0xFF9b59b6),
        fontWeight: FontWeight.w500,
      ),
      'footnote': TextStyle(
        color: isDarkMode ? const Color(0xFF61AFEF) : const Color(0xFF3498db),
        fontSize: 12,
      ),
      'mathInline': TextStyle(
        fontStyle: FontStyle.italic,
        color: isDarkMode ? const Color(0xFFC678DD) : const Color(0xFF9b59b6),
      ),
      'checkbox': TextStyle(color: textColor, fontSize: 16),
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

    final Map<Type, Action<Intent>> actions =
        activeTab != null
            ? {
              SaveIntent: SaveAction(this),
              ToggleBoldIntent: ToggleBoldAction(
                activeTab.controller as MarkdownController,
              ),
              ToggleItalicAction: ToggleItalicAction(
                activeTab.controller as MarkdownController,
              ),
              IndentIntent: IndentAction(
                activeTab.controller as MarkdownController,
              ),
              OutdentIntent: OutdentAction(
                activeTab.controller as MarkdownController,
              ),
            }
            : {};

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
                        ? SingleChildScrollView(
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
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final markdownStyles = _getMarkdownStyles(isDarkMode);

    (activeTab.controller as MarkdownController).updateStyles(markdownStyles);

    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: activeTab.controller,
        focusNode: activeTab.focusNode,
        style: TextStyle(
          fontSize: 16,
          color: isDarkMode ? Colors.white : const Color(0xFF2c3e50),
          height: 1.6,
          fontFamily: 'system-ui',
        ),
        maxLines: null,
        expands: false,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        cursorColor: isDarkMode ? Colors.white : Colors.black,
        cursorWidth: 1.0,
        decoration: const InputDecoration.collapsed(
          hintText: "메모를 시작하세요...",
          hintStyle: TextStyle(
            color: Color(0xFFbdc3c7),
            fontSize: 15,
            height: 1.6,
          ),
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

    final content = activeTab.controller.text;
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

    final content = activeTab.controller.text.trim();
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
