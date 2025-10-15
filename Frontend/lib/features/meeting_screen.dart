// lib/features/meeting_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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

// ✨ [추가] 상수 정의
class EditorConstants {
  static const double suggestionBoxWidth = 400;
  static const double suggestionBoxMaxHeight = 300;
  // static const double suggestionItemHeight = 50;
  static const double suggestionItemFontSize = 12;
  static const double headerHeight = 45;
  static const double editorHorizontalPadding = 20.0;
  static const double editorVerticalPadding = 8.0;
  static const int minContentLengthForSummary = 50;
  static const int webViewInitTimeout = 15;
}

// ✨ [추가] 사용자 정의 예외
class EditorNotFoundException implements Exception {
  final String message;
  EditorNotFoundException([this.message = '에디터를 찾을 수 없습니다.']);
}

class EmptyContentException implements Exception {
  final String message;
  EmptyContentException([this.message = '내용이 비어있습니다.']);
}

// ✨ [추가] 파일 검색 캐시
class FileSearchCache {
  final Map<String, List<FileSystemEntry>> _cache = {};

  void clear() => _cache.clear();

  List<FileSystemEntry> search(String query, List<FileSystemEntry> files) {
    if (_cache.containsKey(query)) return _cache[query]!;

    final result =
        files.where((file) {
          final name = p.basenameWithoutExtension(file.name).toLowerCase();
          return _fuzzyMatch(name, query.toLowerCase());
        }).toList();

    _cache[query] = result;
    return result;
  }

  bool _fuzzyMatch(String text, String pattern) {
    if (pattern.isEmpty) return true;
    int patternIdx = 0;
    for (int i = 0; i < text.length && patternIdx < pattern.length; i++) {
      if (text[i] == pattern[patternIdx]) patternIdx++;
    }
    return patternIdx == pattern.length;
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

  OverlayEntry? _overlayEntry;
  List<FileSystemEntry> _filteredFiles = [];
  int _highlightedIndex = -1;

  final Map<String, GlobalKey<CodeMirrorEditorState>> _editorKeys = {};
  final GlobalKey _editorAreaKey = GlobalKey();

  bool _showMarkdownSyntax = false;

  // ✨ [추가] 검색 캐시
  final FileSearchCache _searchCache = FileSearchCache();

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
    _hideSuggestionBox();
    _titleController.dispose();
    _titleFocusNode.dispose();
    _searchCache.clear();
    super.dispose();
  }

  void _onTabChange() {
    final tabProvider = context.read<TabProvider>();
    final activeTab = tabProvider.activeTab;

    // ✨ [추가] 닫힌 탭의 에디터 키 정리 (메모리 누수 방지)
    _editorKeys.removeWhere(
      (id, _) => !tabProvider.openTabs.any((tab) => tab.id == id),
    );

    if (activeTab != null) {
      if (_titleController.text != activeTab.title) {
        _titleController.text = activeTab.title;
      }
      if (!_editorKeys.containsKey(activeTab.id)) {
        _editorKeys[activeTab.id] = GlobalKey<CodeMirrorEditorState>();
      }
    }

    if (activeTab == null && _titleController.text.isNotEmpty) {
      _titleController.clear();
    }
    _onNoteChange();
    _hideSuggestionBox();
    _searchCache.clear(); // ✨ [추가] 탭 변경 시 캐시 초기화
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
      try {
        final content = await File(selectedEntry.path).readAsString();
        // ✨ [추가] mounted 체크
        if (!mounted) return;
        context.read<TabProvider>().openNewTab(
          filePath: selectedEntry.path,
          content: content,
        );
        fileProvider.setSelectedFileForMeetingScreen(null);
      } catch (e) {
        if (!mounted) return;
        context.read<StatusBarProvider>().showStatusMessage(
          '파일 로드 오류: $e',
          type: StatusType.error,
        );
      }
    }
  }

  // ✨ [수정] Race condition 해결 - postFrameCallback 사용
  void _handleWikiLinkSuggestions(String query, double dx, double dy) {
    _updateFilteredFiles(query);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showSuggestionBox(dx, dy);
      }
    });
  }

  void _handleHighlightSuggestion(int index) {
    if (!mounted) return;
    setState(() {
      _highlightedIndex = index;
    });
    _overlayEntry?.markNeedsBuild();
  }

  void _handleSelectSuggestion() {
    if (_highlightedIndex >= 0 && _highlightedIndex < _filteredFiles.length) {
      final file = _filteredFiles[_highlightedIndex];
      final fileName = p.basenameWithoutExtension(file.name);
      getActiveEditor()?.insertWikiLink(fileName);
      _hideSuggestionBox();
    }
  }

  // ✨ [수정] 검색 캐시 사용
  void _updateFilteredFiles(String query) {
    final allFiles = context.read<FileSystemProvider>().allMarkdownFiles;
    setState(() {
      _filteredFiles = _searchCache.search(query, allFiles);
    });
    getActiveEditor()?.updateSuggestionCount(_filteredFiles.length);
    _overlayEntry?.markNeedsBuild();
  }

  // ✨ [수정] 오버레이 위치 계산 분리
  Offset? _calculateOverlayPosition(double dx, double dy) {
    final RenderBox? renderBox =
        _editorAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    // 에디터 위젯의 전역 좌표
    final editorGlobalOffset = renderBox.localToGlobal(Offset.zero);

    // JavaScript에서 받은 좌표는 이미 에디터 내부 상대 좌표
    // 따라서 에디터의 전역 위치에 단순히 더하기만 하면 됨
    return Offset(editorGlobalOffset.dx + dx, editorGlobalOffset.dy + dy);
  }

  void _showSuggestionBox(double dx, double dy) {
    _hideSuggestionBox();

    final position = _calculateOverlayPosition(dx, dy);
    if (position == null) return;

    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // ✨ [추가] 화면 크기 및 경계 체크
    final screenSize = MediaQuery.of(context).size;
    final suggestionBoxHeight = (_filteredFiles.length *
            40.0) // 평균 아이템 높이를 40.0 정도로 예상하여 계산
        .clamp(50.0, EditorConstants.suggestionBoxMaxHeight); // 최소/최대 높이 제한

    double finalLeft = position.dx;
    double finalTop = position.dy;

    // 좌우 경계 체크
    if (finalLeft + EditorConstants.suggestionBoxWidth > screenSize.width) {
      finalLeft = screenSize.width - EditorConstants.suggestionBoxWidth - 10;
    }
    if (finalLeft < 10) {
      finalLeft = 10;
    }

    // 상하 경계 체크
    if (finalTop + suggestionBoxHeight > screenSize.height) {
      // 화면 밖으로 나가면 커서 위쪽에 표시
      finalTop = position.dy - suggestionBoxHeight - 20; // 20은 커서 높이 추정

      // 위쪽도 화면 밖이면 최대한 보이도록 조정
      if (finalTop < 10) {
        finalTop = 10;
      }
    }

    _overlayEntry = OverlayEntry(
      builder:
          (context) => Positioned(
            left: finalLeft,
            top: finalTop,
            child: _buildSuggestionOverlay(theme, isDarkMode),
          ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  // ✨ [추가] 위젯 분리
  Widget _buildSuggestionOverlay(ThemeData theme, bool isDarkMode) {
    return Material(
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300,
          width: 1.0,
        ),
      ),
      color: isDarkMode ? const Color(0xFF2E2E2E) : theme.cardColor,
      child: Container(
        width: EditorConstants.suggestionBoxWidth,
        constraints: const BoxConstraints(
          maxHeight: EditorConstants.suggestionBoxMaxHeight,
        ),
        child:
            _filteredFiles.isEmpty
                ? const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Center(child: Text('일치하는 파일 없음')),
                )
                : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: _filteredFiles.length,
                  itemBuilder:
                      (context, index) => _buildSuggestionItem(
                        _filteredFiles[index],
                        index,
                        theme,
                      ),
                ),
      ),
    );
  }

  // ✨ [추가] 제안 항목 위젯 분리
  Widget _buildSuggestionItem(
    FileSystemEntry file,
    int index,
    ThemeData theme,
  ) {
    final fileName = p.basenameWithoutExtension(file.name);
    final isHighlighted = index == _highlightedIndex;

    // --- 여기부터 수정 ---

    // 노트 루트 폴더 경로를 가져와서 상대 경로 계산
    final fileProvider = context.read<FileSystemProvider>();
    final rootPathFuture = fileProvider.getOrCreateNoteFolderPath();

    return FutureBuilder<String>(
      future: rootPathFuture,
      builder: (context, snapshot) {
        String relativePath = '';
        if (snapshot.hasData) {
          // 파일의 부모 디렉토리 경로만 추출
          final parentDir = p.dirname(file.path);
          // 루트 폴더와 같지 않은 경우에만 상대 경로 표시
          if (parentDir != snapshot.data) {
            relativePath =
                '${p.relative(parentDir, from: snapshot.data)}${p.separator}';
          }
        }

        return InkWell(
          onTap: () {
            getActiveEditor()?.insertWikiLink(fileName);
            _hideSuggestionBox();
          },
          child: Container(
            // height: EditorConstants.suggestionItemHeight,
            color: isHighlighted ? theme.hoverColor : null,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 파일 제목 (첫째 줄)
                Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 13, // 폰트 크기 조정
                    fontWeight: FontWeight.w500, // 약간 굵게
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                // 파일 상대 경로 (둘째 줄)
                if (relativePath.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1.0), // 제목과의 간격
                    child: Text(
                      relativePath,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.6,
                        ),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    // --- 여기까지 수정 ---
  }

  void _hideSuggestionBox() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() {
        _highlightedIndex = -1;
      });
    }
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

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildNewHeader(tabProvider),
          Expanded(
            child:
                activeTab != null
                    ? Padding(
                      key: _editorAreaKey,
                      padding: const EdgeInsets.symmetric(
                        horizontal: EditorConstants.editorHorizontalPadding,
                        vertical: EditorConstants.editorVerticalPadding,
                      ),
                      child: _buildMarkdownEditor(activeTab),
                    )
                    : Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: EditorConstants.editorHorizontalPadding,
                        vertical: EditorConstants.editorVerticalPadding,
                      ),
                      child: _buildEmptyScreen(),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownEditor(NoteTab activeTab) {
    if (!_editorKeys.containsKey(activeTab.id)) {
      _editorKeys[activeTab.id] = GlobalKey<CodeMirrorEditorState>();
    }
    return CodeMirrorEditor(
      key: _editorKeys[activeTab.id],
      controller: activeTab.controller,
      onSaveRequested: _saveMarkdown,
      onWikiLinkSuggestionsRequested: _handleWikiLinkSuggestions,
      onHideWikiLinkSuggestions: _hideSuggestionBox,
      onHighlightSuggestion: _handleHighlightSuggestion,
      onSelectSuggestion: _handleSelectSuggestion,
      onWikiLinkClicked: _handleWikiLinkClicked, // ✨ [추가]
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
      height: EditorConstants.headerHeight,
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
                  setState(() => _isEditingTitle = false);
                },
                onTapOutside: (_) {
                  _renameCurrentFile(_titleController.text.trim());
                  setState(() => _isEditingTitle = false);
                },
              )
              : InkWell(
                onTap:
                    activeTab == null
                        ? null
                        : () {
                          setState(() => _isEditingTitle = true);
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
                      case 'toggle_syntax':
                        setState(() {
                          _showMarkdownSyntax = !_showMarkdownSyntax;
                        });
                        getActiveEditor()?.toggleFormatting(
                          _showMarkdownSyntax,
                        );
                        break;
                    }
                  },
                  itemBuilder:
                      (BuildContext context) => <PopupMenuEntry<String>>[
                        CompactPopupMenuItem<String>(
                          value: 'toggle_syntax',
                          child: Row(
                            children: [
                              Icon(
                                _showMarkdownSyntax
                                    ? Icons.check_box_outlined
                                    : Icons.check_box_outline_blank,
                                size: 14,
                                color:
                                    isDarkMode
                                        ? Colors.white70
                                        : Colors.black87,
                              ),
                              const SizedBox(width: 8),
                              const Text('문법 표기'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1.0),
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

    try {
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
    } catch (e) {
      _showError('파일 이름 변경 실패: $e');
      _titleController.text = activeTab.title;
    }
  }

  // ✨ [추가] 통합 에러 처리 메서드
  void _showError(String message) {
    if (!mounted) return;
    context.read<StatusBarProvider>().showStatusMessage(
      message,
      type: StatusType.error,
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    context.read<StatusBarProvider>().showStatusMessage(
      message,
      type: StatusType.success,
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    context.read<StatusBarProvider>().showStatusMessage(
      message,
      type: StatusType.info,
    );
  }

  // ✨ [수정] 강화된 에러 핸들링
  Future<void> _saveMarkdown() async {
    try {
      final tabProvider = context.read<TabProvider>();
      final activeTab = tabProvider.activeTab;
      if (activeTab == null) {
        throw EditorNotFoundException('활성 탭이 없습니다.');
      }

      final editor = getActiveEditor();
      if (editor == null) {
        throw EditorNotFoundException();
      }

      final content = await editor.getText();
      if (content.isEmpty) {
        throw EmptyContentException('저장할 내용이 없습니다.');
      }

      final fileProvider = context.read<FileSystemProvider>();

      if (kIsWeb) {
        final fileName = '${activeTab.title}.md';
        web_helper.downloadMarkdownWeb(content, fileName);
        _showSuccess('파일 다운로드 시작: $fileName ✅');
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
        await File(path).writeAsString(content);
        fileProvider.updateLastSavedDirectoryPath(p.dirname(path));
        tabProvider.updateTabInfo(tabProvider.activeTabIndex, path);
        fileProvider.scanForFileSystem();
        _showSuccess('저장 완료: ${p.basename(path)} ✅');
      } else {
        _showInfo('저장이 취소되었습니다.');
      }
    } on EditorNotFoundException catch (e) {
      _showError(e.message);
    } on EmptyContentException catch (e) {
      _showError(e.message);
    } on FileSystemException catch (e) {
      _showError('파일 시스템 오류: ${e.message}');
    } catch (e) {
      _showError('파일 저장 중 오류 발생: $e');
    }
  }

  Future<void> _loadMarkdownFromFilePicker() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt'],
      );

      if (result == null) {
        _showInfo('파일 불러오기가 취소되었습니다.');
        return;
      }

      String content;
      String? filePath;

      if (kIsWeb) {
        final fileBytes = result.files.single.bytes;
        if (fileBytes == null) {
          throw Exception('파일 데이터를 읽을 수 없습니다.');
        }
        content = String.fromCharCodes(fileBytes);
      } else {
        filePath = result.files.single.path;
        if (filePath == null) {
          throw Exception('파일 경로를 찾을 수 없습니다.');
        }
        content = await File(filePath).readAsString();
        if (!mounted) return;
        context.read<FileSystemProvider>().updateLastSavedDirectoryPath(
          p.dirname(filePath),
        );
      }

      if (!mounted) return;
      context.read<TabProvider>().openNewTab(
        filePath: filePath,
        content: content,
      );
      _showSuccess(
        '파일 불러오기 완료: ${p.basename(filePath ?? result.files.single.name)} ✅',
      );
    } catch (e) {
      _showError('파일 불러오기 실패: $e');
    }
  }

  Future<void> _summarizeContent() async {
    try {
      final activeTab = context.read<TabProvider>().activeTab;
      if (activeTab == null) {
        throw EditorNotFoundException('활성 탭이 없습니다.');
      }

      final editor = getActiveEditor();
      if (editor == null) {
        throw EditorNotFoundException();
      }

      final content = (await editor.getText()).trim();
      if (content.length < EditorConstants.minContentLengthForSummary) {
        throw EmptyContentException(
          '요약할 내용이 너무 짧습니다 (최소 ${EditorConstants.minContentLengthForSummary}자 필요).',
        );
      }

      final bottomController = context.read<BottomSectionController>();
      bottomController.setIsLoading(true);
      bottomController.updateSummary('AI가 텍스트를 요약 중입니다...');

      final summary = await callBackendTask(
        taskType: "summarize",
        text: content,
      );

      if (!mounted) return;
      bottomController.updateSummary(summary ?? '요약에 실패했거나 내용이 없습니다.');
    } on EditorNotFoundException catch (e) {
      _showError(e.message);
    } on EmptyContentException catch (e) {
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      context.read<BottomSectionController>().updateSummary('요약 중 오류 발생: $e');
      _showError('텍스트 요약 중 오류 발생: $e');
    } finally {
      if (mounted) {
        context.read<BottomSectionController>().setIsLoading(false);
      }
    }
  }

  // ✨ [추가] 위키링크 클릭 핸들러
  void _handleWikiLinkClicked(String fileName) async {
    final fileProvider = context.read<FileSystemProvider>();
    final tabProvider = context.read<TabProvider>();

    try {
      // 파일 검색
      final allFiles = fileProvider.allMarkdownFiles;
      final targetFile = allFiles.firstWhere(
        (file) => p.basenameWithoutExtension(file.name) == fileName,
        orElse: () => throw Exception('파일을 찾을 수 없습니다: $fileName'),
      );

      // 파일 열기
      final content = await File(targetFile.path).readAsString();
      if (!mounted) return;

      tabProvider.openNewTab(filePath: targetFile.path, content: content);

      _showSuccess('파일 열기 완료: $fileName ✅');
    } catch (e) {
      _showError('파일 열기 실패: $e');
    }
  }

  Future<String> _getNotesDirectoryPath() async {
    try {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null) {
        throw Exception('사용자 홈 디렉터리를 찾을 수 없습니다.');
      }
      final folderPath = p.join(home, 'Documents', 'Memordo_Notes');
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return folderPath;
    } catch (e) {
      // 폴백: 현재 디렉터리 반환
      return Directory.current.path;
    }
  }
}
