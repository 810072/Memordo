// Frontend/lib/layout/main_layout.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert'; // jsonEncode를 위해 추가
import 'package:desktop_multi_window/desktop_multi_window.dart'; // 패키지 임포트

// 기존 임포트
import 'left_sidebar_content.dart';
import 'right_sidebar_content.dart';
import '../features/page_type.dart';
import '../features/meeting_screen.dart';
import '../features/calendar_page.dart';
import '../features/graph_page.dart';
import '../features/history.dart';
import '../features/settings_page.dart';
import '../features/search_page.dart';
import '../providers/file_system_provider.dart';
import '../providers/token_status_provider.dart';
import '../layout/bottom_section_controller.dart';

class MainLayout extends StatefulWidget {
  final PageType activePage;
  final ValueChanged<PageType> onPageSelected;

  const MainLayout({
    Key? key,
    required this.activePage,
    required this.onPageSelected,
  }) : super(key: key);

  @override
  _MainLayoutState createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isLeftExpanded = true;
  bool _isRightExpanded = true;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _pages =
        PageType.values.map((pageType) => _getPageWidget(pageType)).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TokenStatusProvider>(
        context,
        listen: false,
      ).loadStatus(context);
    });
  }

  void _openChatbotWindow() async {
    final window = await DesktopMultiWindow.createWindow(
      jsonEncode({'arg1': 'value1', 'arg2': 'value2'}),
    );
    window
      ..setFrame(const Offset(100, 100) & const Size(560, 960))
      ..center()
      ..setTitle('Memordo 챗봇')
      ..show();
  }

  Widget _getPageWidget(PageType pageType) {
    switch (pageType) {
      case PageType.home:
        return const MeetingScreen();
      case PageType.history:
        return const HistoryPage();
      case PageType.calendar:
        return const CalendarPage();
      case PageType.graph:
        return const GraphPage();
      case PageType.settings:
        return const SettingsPage();
      case PageType.search:
        return const SearchPage();
      default:
        return const Center(child: Text('알 수 없는 페이지'));
    }
  }

  bool get _showRightSidebar => widget.activePage == PageType.home;

  void _toggleLeftPanel() {
    setState(() {
      _isLeftExpanded = !_isLeftExpanded;
    });
  }

  void _toggleRightPanel() {
    setState(() {
      _isRightExpanded = !_isRightExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showRightPanelButton = _showRightSidebar;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(45.0),
        child: AppBar(
          // ✨ [수정] elevation을 0으로 하고, shape를 사용하여 하단에 선을 추가합니다.
          elevation: 0,
          shape: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
          ),
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFF475569)),
            onPressed: _toggleLeftPanel,
            tooltip: 'Toggle Sidebar',
          ),
          title: const Row(
            children: [
              Icon(Icons.note_alt_rounded, color: Color(0xFF3d98f4)),
              SizedBox(width: 8),
              Text(
                'Memordo',
                style: TextStyle(
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  fontFamily: 'Work Sans',
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.smart_toy_outlined,
                color: Color(0xFF475569),
              ),
              onPressed: _openChatbotWindow,
              tooltip: '챗봇 열기',
            ),
            const SizedBox(width: 4),
            if (showRightPanelButton)
              IconButton(
                icon: const Icon(
                  Icons.menu_open_outlined,
                  color: Color(0xFF475569),
                ),
                onPressed: _toggleRightPanel,
                tooltip: 'Toggle Memos',
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.grey.shade300,
                child: Icon(Icons.person_outline, color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: _isLeftExpanded ? 192 : 52,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              // ✨ [수정] 구분선 색상을 테마에서 가져옵니다.
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: LeftSidebarContent(
              isExpanded: _isLeftExpanded,
              activePage: widget.activePage,
              onPageSelected: widget.onPageSelected,
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: widget.activePage.index,
              children: _pages,
            ),
          ),
          if (_showRightSidebar)
            ResizableRightSidebar(
              isVisible: _isRightExpanded,
              child: Consumer<FileSystemProvider>(
                builder: (context, fileSystemProvider, child) {
                  return RightSidebarContent(
                    isLoading: fileSystemProvider.isLoading,
                    fileSystemEntries: fileSystemProvider.fileSystemEntries,
                    onEntryTap: (entry) {
                      if (entry.isDirectory) {
                        debugPrint('폴더는 로드할 수 없습니다: ${entry.name}');
                        return;
                      }
                      context.read<BottomSectionController>().setActiveTab(0);
                      widget.onPageSelected(PageType.home);
                      fileSystemProvider.setSelectedFileForMeetingScreen(entry);
                    },
                    onRefresh: fileSystemProvider.scanForFileSystem,
                    onRenameEntry: (entry) async {
                      String? newName = await _showTextInputDialog(
                        context,
                        '이름 변경',
                        '새 이름을 입력하세요.',
                        initialValue: entry.name,
                      );
                      if (newName != null &&
                          newName.isNotEmpty &&
                          newName != entry.name) {
                        fileSystemProvider.renameEntry(context, entry, newName);
                      }
                    },
                    onDeleteEntry:
                        (entry) =>
                            fileSystemProvider.deleteEntry(context, entry),
                    sidebarIsExpanded: _isRightExpanded,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

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
}

class ResizableRightSidebar extends StatefulWidget {
  final Widget child;
  final bool isVisible;

  const ResizableRightSidebar({
    Key? key,
    required this.child,
    required this.isVisible,
  }) : super(key: key);

  @override
  _ResizableRightSidebarState createState() => _ResizableRightSidebarState();
}

class _ResizableRightSidebarState extends State<ResizableRightSidebar> {
  double _width = 200.0;
  bool _isResizing = false;

  @override
  Widget build(BuildContext context) {
    final sidebarContent = Container(
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: ClipRect(child: widget.child),
    );

    final resizableContainer =
        _isResizing
            ? Container(width: _width, child: sidebarContent)
            : AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: widget.isVisible ? _width : 0,
              child: sidebarContent,
            );

    return Row(
      children: [
        if (widget.isVisible)
          GestureDetector(
            onHorizontalDragStart: (_) => setState(() => _isResizing = true),
            onHorizontalDragUpdate: (details) {
              setState(() {
                _width -= details.delta.dx;
                _width = _width.clamp(180.0, 500.0);
              });
            },
            onHorizontalDragEnd: (_) => setState(() => _isResizing = false),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: Container(
                width: 8,
                color: Colors.transparent,
                alignment: Alignment.center,
                child: Container(
                  width: 1,
                  // ✨ [수정] 구분선 색상을 테마에서 가져옵니다.
                  color:
                      _isResizing
                          ? Theme.of(context).primaryColor
                          : Theme.of(context).dividerColor,
                ),
              ),
            ),
          ),
        resizableContainer,
      ],
    );
  }
}
