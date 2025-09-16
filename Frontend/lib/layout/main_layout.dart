// Frontend/lib/layout/main_layout.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

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

class MainLayout extends StatefulWidget {
  final PageType activePage;
  final ValueChanged<PageType> onPageSelected;
  final String? initialTextForMemo;

  const MainLayout({
    Key? key,
    required this.activePage,
    required this.onPageSelected,
    this.initialTextForMemo,
  }) : super(key: key);

  @override
  _MainLayoutState createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isRightExpanded = true;
  double _rightSidebarWidth = 160.0;
  bool _isResizing = false;

  @override
  void initState() {
    super.initState();
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
        return MeetingScreen(
          key: ValueKey(widget.initialTextForMemo),
          initialText: widget.initialTextForMemo,
        );
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

  void _toggleRightPanel() {
    setState(() {
      _isRightExpanded = !_isRightExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages =
        PageType.values.map((pageType) => _getPageWidget(pageType)).toList();
    final bool showRightPanelButton = _showRightSidebar;
    final dividerColor = Theme.of(context).dividerColor;

    return Scaffold(
      body: Row(
        children: [
          // --- 1. 좌측 고정 사이드바 ---
          Container(
            width: 40,
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                // ✨ [삭제] AppBar 높이만큼 있던 공간을 제거합니다.
                Expanded(
                  child: LeftSidebarContent(
                    isExpanded: false,
                    activePage: widget.activePage,
                    onPageSelected: widget.onPageSelected,
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(thickness: 1, width: 1, color: dividerColor),

          // --- 2. 우측 리사이즈 가능 사이드바 (조건부 표시) ---
          if (_showRightSidebar && _isRightExpanded)
            Row(
              children: [
                Container(
                  width: _rightSidebarWidth,
                  color: Theme.of(context).cardColor,
                  child: Column(
                    children: [
                      // ✨ [삭제] AppBar 높이만큼 있던 공간을 제거합니다.
                      Expanded(
                        child: Consumer<FileSystemProvider>(
                          builder: (context, fileSystemProvider, child) {
                            return RightSidebarContent(
                              isLoading: fileSystemProvider.isLoading,
                              fileSystemEntries:
                                  fileSystemProvider.fileSystemEntries,
                              onEntryTap: (entry) {
                                if (entry.isDirectory) {
                                  debugPrint('폴더는 로드할 수 없습니다: ${entry.name}');
                                  return;
                                }
                                context
                                    .read<BottomSectionController>()
                                    .setActiveTab(0);
                                widget.onPageSelected(PageType.home);
                                fileSystemProvider
                                    .setSelectedFileForMeetingScreen(entry);
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
                                  fileSystemProvider.renameEntry(
                                    context,
                                    entry,
                                    newName,
                                  );
                                }
                              },
                              onDeleteEntry:
                                  (entry) => fileSystemProvider.deleteEntry(
                                    context,
                                    entry,
                                  ),
                              sidebarIsExpanded: _isRightExpanded,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // --- 리사이즈 핸들러 ---
                GestureDetector(
                  onHorizontalDragStart:
                      (_) => setState(() => _isResizing = true),
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _rightSidebarWidth += details.delta.dx;
                      _rightSidebarWidth = _rightSidebarWidth.clamp(
                        160.0,
                        500.0,
                      );
                    });
                  },
                  onHorizontalDragEnd:
                      (_) => setState(() => _isResizing = false),
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
                                : dividerColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),

          // --- 3. 메인 콘텐츠 영역 ---
          Expanded(
            child: Column(
              children: [
                // --- 커스텀 AppBar ---
                DragToMoveArea(
                  child: Container(
                    height: 40.0,
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.smart_toy_outlined,
                            color: Color(0xFF475569),
                          ),
                          onPressed: _openChatbotWindow,
                          tooltip: '챗봇 열기',
                        ),
                        _buildUserProfileIcon(context),
                        const WindowButtons(),
                      ],
                    ),
                  ),
                ),
                Divider(thickness: 1, height: 1, color: dividerColor),
                // --- 페이지 콘텐츠 ---
                Expanded(
                  child: IndexedStack(
                    index: widget.activePage.index,
                    children: pages,
                  ),
                ),
              ],
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

class WindowButtons extends StatelessWidget {
  const WindowButtons({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.minimize, size: 16),
          onPressed: () => windowManager.minimize(),
          tooltip: 'Minimize',
          color: const Color(0xFF475569),
        ),
        IconButton(
          icon: const Icon(Icons.crop_square, size: 16),
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
          tooltip: 'Maximize',
          color: const Color(0xFF475569),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          onPressed: () => windowManager.close(),
          tooltip: 'Close',
          color: const Color(0xFF475569),
          hoverColor: Colors.red.withOpacity(0.1),
        ),
      ],
    );
  }
}
