// lib/layout/main_layout.dart

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
import '../providers/tab_provider.dart';
import '../viewmodels/history_viewmodel.dart';
import '../viewmodels/calendar_viewmodel.dart'; // ✨ [추가] CalendarViewModel 임포트

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

  Widget _buildTabList(TabProvider tabProvider) {
    final theme = Theme.of(context);
    if (tabProvider.openTabs.isEmpty) {
      return const SizedBox.shrink(); // 탭이 없으면 빈 공간
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const double defaultTabWidth = 160.0;
        const double minTabWidth = 80.0;
        final double totalWidth = constraints.maxWidth;
        final int tabCount = tabProvider.openTabs.length;
        double tabWidth = defaultTabWidth;

        if (tabCount * defaultTabWidth > totalWidth) {
          tabWidth = totalWidth / tabCount;
          if (tabWidth < minTabWidth) {
            tabWidth = minTabWidth;
          }
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(tabCount, (index) {
              return Row(
                children: [
                  _TabItem(
                    tab: tabProvider.openTabs[index],
                    isActive: index == tabProvider.activeTabIndex,
                    onTap: () => tabProvider.setActiveTab(index),
                    onClose: () => tabProvider.closeTab(index),
                    width: tabWidth,
                  ),
                  if (index < tabCount - 1)
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: theme.dividerColor,
                    ),
                ],
              );
            }),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages =
        PageType.values.map((pageType) => _getPageWidget(pageType)).toList();
    final dividerColor = Theme.of(context).dividerColor;

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 40,
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
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

          if (_showRightSidebar && _isRightExpanded)
            Row(
              children: [
                Container(
                  width: _rightSidebarWidth,
                  color: Theme.of(context).cardColor,
                  child: Column(
                    children: [
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
                                    .read<FileSystemProvider>()
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

          Expanded(
            child: Column(
              children: [
                DragToMoveArea(
                  child: Container(
                    height: 40.0,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border(
                        bottom: BorderSide(color: dividerColor, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (widget.activePage == PageType.home)
                          Expanded(
                            child: Consumer<TabProvider>(
                              builder: (context, tabProvider, child) {
                                return _buildTabList(tabProvider);
                              },
                            ),
                          ),
                        if (widget.activePage == PageType.history)
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Text(
                              '방문 기록',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                        // ✨ [추가] 캘린더 페이지 제목
                        if (widget.activePage == PageType.calendar)
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Text(
                              'Calendar',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                        if (widget.activePage != PageType.home) const Spacer(),
                        if (widget.activePage == PageType.home)
                          Consumer<TabProvider>(
                            builder:
                                (context, tabProvider, child) => IconButton(
                                  icon: const Icon(Icons.add, size: 18),
                                  onPressed: () => tabProvider.openNewTab(),
                                  tooltip: '새 메모',
                                  splashRadius: 18,
                                  constraints: const BoxConstraints(
                                    maxWidth: 36,
                                    maxHeight: 36,
                                  ),
                                ),
                          ),
                        if (widget.activePage == PageType.history)
                          Consumer<HistoryViewModel>(
                            builder: (context, viewModel, child) {
                              final tokenProvider =
                                  context.watch<TokenStatusProvider>();
                              return Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.refresh, size: 20),
                                    tooltip: '새로고침',
                                    color: const Color(0xFF475569),
                                    onPressed:
                                        viewModel.isLoading ||
                                                !tokenProvider.isAuthenticated
                                            ? null
                                            : () =>
                                                viewModel.loadVisitHistory(),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.auto_awesome_outlined,
                                      size: 20,
                                    ),
                                    tooltip: '선택 항목 요약',
                                    color: const Color(0xFF475569),
                                    onPressed:
                                        viewModel.isLoading ||
                                                !tokenProvider.isAuthenticated
                                            ? null
                                            : () => viewModel
                                                .summarizeSelection(context),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              );
                            },
                          ),
                        // ✨ [추가] 캘린더 페이지 액션 버튼 (Today)
                        if (widget.activePage == PageType.calendar)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Consumer<CalendarViewModel>(
                              builder: (context, viewModel, child) {
                                return ElevatedButton(
                                  onPressed: () => viewModel.jumpToToday(),
                                  child: const Text('Today'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3d98f4),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    elevation: 0,
                                  ),
                                );
                              },
                            ),
                          ),
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

class _TabItem extends StatefulWidget {
  final dynamic tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final double width;

  const _TabItem({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.width,
  });

  @override
  __TabItemState createState() => __TabItemState();
}

class __TabItemState extends State<_TabItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          width: widget.width,
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 8),
          transform:
              widget.isActive ? Matrix4.translationValues(0, 1, 0) : null,
          decoration: BoxDecoration(
            color:
                widget.isActive
                    ? theme.scaffoldBackgroundColor
                    : Colors.transparent,
            border:
                widget.isActive
                    ? Border(
                      top: BorderSide(color: theme.primaryColor, width: 2),
                    )
                    : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.tab.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        widget.isActive
                            ? theme.textTheme.bodyLarge?.color
                            : theme.textTheme.bodyMedium?.color?.withOpacity(
                              0.7,
                            ),
                    fontSize: 13,
                    fontWeight:
                        widget.isActive ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                child:
                    (widget.isActive || _isHovered)
                        ? InkWell(
                          onTap: widget.onClose,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.close,
                              size: 15,
                              color:
                                  widget.isActive
                                      ? theme.textTheme.bodyLarge?.color
                                      : theme.textTheme.bodyMedium?.color
                                          ?.withOpacity(0.7),
                            ),
                          ),
                        )
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
