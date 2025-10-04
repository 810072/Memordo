// lib/layout/main_layout.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../features/notification_log_page.dart';
import '../providers/file_system_provider.dart';
import '../providers/token_status_provider.dart';
import '../providers/tab_provider.dart';
import '../viewmodels/history_viewmodel.dart';
import '../viewmodels/calendar_viewmodel.dart';
import '../viewmodels/graph_viewmodel.dart';
import '../widgets/status_bar_widget.dart';
import 'bottom_section_controller.dart';
import '../widgets/ai_summary_widget.dart';

class MainLayout extends StatefulWidget {
  final ValueChanged<PageType> onPageSelected;
  final String? initialTextForMemo;

  const MainLayout({
    Key? key,
    required this.onPageSelected,
    this.initialTextForMemo,
  }) : super(key: key);

  @override
  _MainLayoutState createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  PageType _activePage = PageType.home;

  // 오른쪽 사이드바 너비 조절 관련 상태 변수
  bool _isRightExpanded = true;
  double _rightSidebarWidth = 180.0; // 기본 너비 조정
  bool _isResizing = false;
  bool _isHoveringResizer = false;

  final ScrollController _tabScrollController = ScrollController();

  // 하단 패널 관련 상태 변수
  bool _isBottomPanelVisible = false;
  double _bottomPanelHeight = 200.0;
  bool _isResizingBottomPanel = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bottomController = context.read<BottomSectionController>();
      bottomController.addListener(_onBottomControllerUpdate);
      Provider.of<TokenStatusProvider>(
        context,
        listen: false,
      ).loadStatus(context);
    });
  }

  @override
  void dispose() {
    _tabScrollController.dispose();
    if (mounted) {
      context.read<BottomSectionController>().removeListener(
        _onBottomControllerUpdate,
      );
    }
    super.dispose();
  }

  void _onBottomControllerUpdate() {
    if (!mounted) return;
    final controller = context.read<BottomSectionController>();
    if (controller.isLoading && !_isBottomPanelVisible) {
      setState(() {
        _isBottomPanelVisible = true;
      });
    }
  }

  void _toggleBottomPanel() {
    setState(() {
      _isBottomPanelVisible = !_isBottomPanelVisible;
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
        return SettingsPage(onPageChange: (page) => _changePage(page));
      case PageType.search:
        return const SearchPage();
      case PageType.notifications:
        return const NotificationLogPage();
    }
  }

  void _changePage(PageType pageType) {
    widget.onPageSelected(pageType);
    if (mounted) {
      context.read<BottomSectionController>().clearSummary();
    }
    setState(() {
      _activePage = pageType;
    });
  }

  bool get _showRightSidebar =>
      _activePage == PageType.home ||
      _activePage == PageType.history ||
      _activePage == PageType.graph ||
      _activePage == PageType.calendar;

  @override
  Widget build(BuildContext context) {
    final pages =
        PageType.values.map((pageType) => _getPageWidget(pageType)).toList();
    final dividerColor = Theme.of(context).dividerColor;

    // 히스토리 페이지일 때는 너비를 고정하고, 아닐 때는 조절 가능한 너비 사용
    final double currentSidebarWidth =
        _activePage == PageType.history ? 180.0 : _rightSidebarWidth;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // 왼쪽 고정 사이드바
                Container(
                  width: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(
                      right: BorderSide(color: dividerColor, width: 1),
                    ),
                  ),
                  child: LeftSidebarContent(
                    isExpanded: false,
                    activePage: _activePage,
                    onPageSelected: (page) => _changePage(page),
                  ),
                ),

                // 오른쪽 사이드바 (조건부 렌더링)
                if (_showRightSidebar && _isRightExpanded)
                  Row(
                    children: [
                      Container(
                        width: currentSidebarWidth,
                        color: Theme.of(context).cardColor,
                        // ✨ [수정] 리팩토링된 RightSidebarContent 호출
                        child: RightSidebarContent(
                          activePage: _activePage,
                          onEntryTap: (entry) {
                            if (entry.isDirectory) return;
                            context
                                .read<FileSystemProvider>()
                                .setSelectedFileForMeetingScreen(entry);
                          },
                          onDeleteEntry:
                              (entry) => context
                                  .read<FileSystemProvider>()
                                  .deleteEntry(context, entry),
                          // onRenameEntry는 이제 각 사이드바 위젯 내부에서 처리합니다.
                          onRenameEntry:
                              (entry, newName) => context
                                  .read<FileSystemProvider>()
                                  .renameEntry(context, entry, newName),
                        ),
                      ),
                      // 히스토리 페이지가 아닐 때만 너비 조절 핸들 표시
                      if (_activePage != PageType.history)
                        MouseRegion(
                          onEnter:
                              (_) => setState(() => _isHoveringResizer = true),
                          onExit:
                              (_) => setState(() => _isHoveringResizer = false),
                          cursor: SystemMouseCursors.resizeLeftRight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragStart:
                                (_) => setState(() => _isResizing = true),
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                _rightSidebarWidth += details.delta.dx;
                                _rightSidebarWidth = _rightSidebarWidth.clamp(
                                  180.0,
                                  500.0,
                                );
                              });
                            },
                            onHorizontalDragEnd:
                                (_) => setState(() => _isResizing = false),
                            child: Container(
                              width: 1.0,
                              color: Colors.transparent,
                              child: VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color:
                                    (_isResizing || _isHoveringResizer)
                                        ? Theme.of(context).primaryColor
                                        : dividerColor,
                              ),
                            ),
                          ),
                        )
                      else
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: dividerColor,
                        ),
                    ],
                  ),

                // 메인 콘텐츠 영역
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
                              _buildTopBarContent(), // 상단바 내용 분리
                              const Spacer(),
                              _buildTopBarActions(), // 상단바 액션 버튼 분리
                              const WindowButtons(),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _activePage.index,
                          children: pages,
                        ),
                      ),
                      if (_isBottomPanelVisible) _buildSummaryPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          StatusBarWidget(
            onBellPressed: () => _changePage(PageType.notifications),
            onBottomPanelToggle: _toggleBottomPanel,
          ),
        ],
      ),
    );
  }

  // 상단바의 페이지별 제목 또는 탭 리스트를 생성하는 위젯
  Widget _buildTopBarContent() {
    switch (_activePage) {
      case PageType.home:
        return Expanded(
          child: Consumer<TabProvider>(
            builder: (context, tabProvider, child) {
              return _buildTabList(tabProvider);
            },
          ),
        );
      case PageType.history:
        return const _TopBarTitle('방문 기록');
      case PageType.calendar:
        return const _TopBarTitle('Calendar');
      case PageType.graph:
        return const _TopBarTitle('AI 노트 관계도');
      case PageType.settings:
        return const _TopBarTitle('Settings');
      default:
        return const SizedBox.shrink();
    }
  }

  // 상단바의 페이지별 액션 버튼들을 생성하는 위젯
  Widget _buildTopBarActions() {
    switch (_activePage) {
      case PageType.home:
        return Consumer<TabProvider>(
          builder:
              (context, tabProvider, child) => IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => tabProvider.openNewTab(),
                tooltip: '새 메모',
                splashRadius: 18,
                constraints: const BoxConstraints(maxWidth: 36, maxHeight: 36),
              ),
        );
      case PageType.history:
        return Consumer<HistoryViewModel>(
          builder: (context, viewModel, child) {
            final tokenProvider = context.watch<TokenStatusProvider>();
            return Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '새로고침',
                  onPressed:
                      viewModel.isLoading || !tokenProvider.isAuthenticated
                          ? null
                          : () => viewModel.loadVisitHistory(),
                ),
                IconButton(
                  icon: const Icon(Icons.auto_awesome_outlined, size: 20),
                  tooltip: '선택 항목 요약',
                  onPressed:
                      viewModel.isLoading || !tokenProvider.isAuthenticated
                          ? null
                          : () => viewModel.summarizeSelection(context),
                ),
                const SizedBox(width: 8),
              ],
            );
          },
        );
      case PageType.calendar:
        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Consumer<CalendarViewModel>(
            builder: (context, viewModel, child) {
              return ElevatedButton(
                onPressed: () => viewModel.jumpToToday(),
                child: const Text('Today'),
                style: ElevatedButton.styleFrom(
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
                ),
              );
            },
          ),
        );
      case PageType.graph:
        return Consumer<GraphViewModel>(
          builder: (context, viewModel, child) {
            return Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.hub_outlined, size: 20),
                  tooltip: '임베딩 생성 및 새로고침',
                  onPressed:
                      viewModel.isLoading
                          ? null
                          : () => viewModel.triggerEmbeddingProcess(context),
                ),
                IconButton(
                  icon: Icon(
                    viewModel.showUserGraph
                        ? Icons.person_outline
                        : Icons.smart_toy_outlined,
                    size: 20,
                  ),
                  tooltip:
                      viewModel.showUserGraph ? '사용자 정의 링크 보기' : 'AI 추천 관계 보기',
                  onPressed:
                      viewModel.isLoading
                          ? null
                          : () => viewModel.toggleGraphView(),
                ),
                const SizedBox(width: 8),
              ],
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // 탭 리스트 UI
  Widget _buildTabList(TabProvider tabProvider) {
    final theme = Theme.of(context);
    if (tabProvider.openTabs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          final newOffset =
              _tabScrollController.offset + pointerSignal.scrollDelta.dy;
          final clampedOffset = newOffset.clamp(
            _tabScrollController.position.minScrollExtent,
            _tabScrollController.position.maxScrollExtent,
          );
          _tabScrollController.jumpTo(clampedOffset);
        }
      },
      child: ScrollbarTheme(
        data: ScrollbarTheme.of(context).copyWith(crossAxisMargin: 0),
        child: Scrollbar(
          controller: _tabScrollController,
          thumbVisibility: false,
          trackVisibility: false,
          thickness: 2.5,
          radius: const Radius.circular(4.0),
          child: SingleChildScrollView(
            controller: _tabScrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              children: List.generate(tabProvider.openTabs.length, (index) {
                return DragTarget<int>(
                  builder: (context, candidateData, rejectedData) {
                    return Draggable<int>(
                      data: index,
                      feedback: Material(
                        elevation: 4.0,
                        child: _TabItem(
                          tab: tabProvider.openTabs[index],
                          isActive: true,
                          onTap: () {},
                          onClose: () {},
                        ),
                      ),
                      childWhenDragging: Container(
                        height: 40,
                        width: 180,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          _TabItem(
                            tab: tabProvider.openTabs[index],
                            isActive: index == tabProvider.activeTabIndex,
                            onTap: () => tabProvider.setActiveTab(index),
                            onClose: () => tabProvider.closeTab(index),
                          ),
                          if (index < tabProvider.openTabs.length - 1)
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: theme.dividerColor,
                            ),
                        ],
                      ),
                    );
                  },
                  onAccept: (draggedIndex) {
                    tabProvider.reorderTab(draggedIndex, index);
                  },
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  // AI 요약 패널 UI
  Widget _buildSummaryPanel() {
    final theme = Theme.of(context);
    return Container(
      height: _bottomPanelHeight,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onVerticalDragStart:
                (_) => setState(() => _isResizingBottomPanel = true),
            onVerticalDragUpdate: (details) {
              setState(() {
                _bottomPanelHeight -= details.delta.dy;
                _bottomPanelHeight = _bottomPanelHeight.clamp(80.0, 500.0);
              });
            },
            onVerticalDragEnd:
                (_) => setState(() => _isResizingBottomPanel = false),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: Container(
                height: 8,
                color:
                    _isResizingBottomPanel
                        ? theme.primaryColor.withOpacity(0.3)
                        : Colors.transparent,
              ),
            ),
          ),
          Container(
            height: 27,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'AI 요약',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '닫기',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    maxHeight: 27,
                    maxWidth: 27,
                  ),
                  onPressed: _toggleBottomPanel,
                ),
              ],
            ),
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: AiSummaryWidget(),
            ),
          ),
        ],
      ),
    );
  }
}

// 상단바 제목을 위한 작은 위젯
class _TopBarTitle extends StatelessWidget {
  final String title;
  const _TopBarTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }
}

// 창 조절 버튼
class WindowButtons extends StatelessWidget {
  const WindowButtons({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 16),
          onPressed: () => windowManager.minimize(),
          tooltip: 'Minimize',
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
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          onPressed: () => windowManager.close(),
          tooltip: 'Close',
          hoverColor: Colors.red.withOpacity(0.1),
        ),
      ],
    );
  }
}

// 탭 아이템 UI
class _TabItem extends StatefulWidget {
  final dynamic tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final double? width;

  const _TabItem({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    this.width,
  });

  @override
  __TabItemState createState() => __TabItemState();
}

class __TabItemState extends State<_TabItem> {
  bool _isHovered = false;
  bool _isCloseButtonHovered = false;

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
          padding: const EdgeInsets.only(left: 12, right: 4),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.tab.title,
                  softWrap: false,
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
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                height: 24,
                child:
                    (widget.isActive || _isHovered)
                        ? MouseRegion(
                          onEnter:
                              (_) =>
                                  setState(() => _isCloseButtonHovered = true),
                          onExit:
                              (_) =>
                                  setState(() => _isCloseButtonHovered = false),
                          child: InkWell(
                            onTap: widget.onClose,
                            borderRadius: BorderRadius.circular(4.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    _isCloseButtonHovered
                                        ? theme.hoverColor
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: Center(
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
