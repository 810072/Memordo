// Frontend/lib/layout/main_layout.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';

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
import '../auth/login_page.dart';
import '../services/auth_token.dart';

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
  bool _isLeftExpanded = false;
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
          title: Row(
            children: [
              const Icon(Icons.note_alt_rounded, color: Color(0xFF3d98f4)),
              const SizedBox(width: 8),
              Text(
                'Memordo',
                style: TextStyle(
                  // ✨ [수정] 하드코딩된 색상 대신 현재 테마의 AppBar 전경색을 사용합니다.
                  color: Theme.of(context).appBarTheme.foregroundColor,
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
            _buildUserProfileIcon(context),
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

  Widget _buildUserProfileIcon(BuildContext context) {
    return Consumer<TokenStatusProvider>(
      builder: (context, tokenProvider, child) {
        return PopupMenuButton<String>(
          tooltip: '사용자 프로필',
          offset: const Offset(0, 45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          elevation: 8.0,
          color: Theme.of(context).cardColor,
          itemBuilder: (BuildContext context) {
            return _buildUserProfileMenuItems(context, tokenProvider);
          },
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              backgroundColor:
                  tokenProvider.isAuthenticated
                      ? Colors.deepPurple.shade100
                      : Colors.grey.shade300,
              child: Icon(
                Icons.person_outline,
                color:
                    tokenProvider.isAuthenticated
                        ? Colors.deepPurple.shade700
                        : Colors.grey.shade700,
              ),
            ),
          ),
        );
      },
    );
  }

  List<PopupMenuEntry<String>> _buildUserProfileMenuItems(
    BuildContext context,
    TokenStatusProvider provider,
  ) {
    if (provider.isAuthenticated) {
      return [
        PopupMenuItem(
          enabled: false,
          child: Container(
            width: 200,
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.deepPurple.shade100,
                  child: Icon(
                    Icons.person,
                    size: 28,
                    color: Colors.deepPurple.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  provider.userEmail ?? '이메일 정보 없음',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          onTap: () {
            final tokenProvider = Provider.of<TokenStatusProvider>(
              context,
              listen: false,
            );
            tokenProvider.forceLogout(context);
          },
          child: const ListTile(
            leading: Icon(Icons.logout),
            title: Text('로그아웃'),
          ),
        ),
      ];
    } else {
      return [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Guest',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  '로그인이 필요합니다.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.login, size: 16),
                  label: const Text('로그인/회원가입'),
                  onPressed: () {
                    final tokenProvider = Provider.of<TokenStatusProvider>(
                      context,
                      listen: false,
                    );
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => LoginPage()),
                    ).then((_) {
                      tokenProvider.loadStatus(context);
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
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
