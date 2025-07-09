// Frontend/lib/layout/main_layout.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 사용을 위해 추가

import 'left_sidebar_content.dart';
import 'right_sidebar_content.dart'; // RightSidebarContent 임포트 유지
import '../features/page_type.dart';
import '../features/meeting_screen.dart'; // 모든 페이지 위젯 임포트
import '../features/calendar_page.dart';
import '../features/graph_page.dart';
import '../features/history.dart';
import '../features/settings_page.dart';
import '../providers/file_system_provider.dart'; // FileSystemProvider 임포트

class MainLayout extends StatefulWidget {
  final PageType activePage;
  final ValueChanged<PageType> onPageSelected; // 페이지 선택 콜백 추가

  const MainLayout({
    Key? key,
    required this.activePage,
    required this.onPageSelected, // 콜백을 생성자로 받음
  }) : super(key: key);

  @override
  _MainLayoutState createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isLeftExpanded = true;
  bool _isRightExpanded = true;

  // 각 PageType에 해당하는 위젯을 반환하는 함수
  Widget _getPageWidget(PageType pageType) {
    switch (pageType) {
      case PageType.home:
        return MeetingScreen();
      case PageType.history:
        return const HistoryPage();
      case PageType.calendar:
        return const CalendarPage();
      case PageType.graph:
        return const GraphPage();
      case PageType.settings:
        return const SettingsPage();
      default:
        return const Center(child: Text('알 수 없는 페이지'));
    }
  }

  // RightSidebarContent를 표시할지 여부를 결정하는 플래그
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
      backgroundColor: const Color(0xFFF1F5F9), // bg-slate-100
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1.0,
        shadowColor: Colors.black12,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF475569)),
          onPressed: _toggleLeftPanel,
          tooltip: 'Toggle Sidebar',
        ),
        title: Row(
          children: const [
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
      body: Row(
        children: [
          // Left Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: _isLeftExpanded ? 240 : 65,
            child: LeftSidebarContent(
              isExpanded: _isLeftExpanded,
              activePage: widget.activePage,
              onPageSelected: widget.onPageSelected,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
            ),
          ),
          // Main Content Area (IndexedStack 사용)
          Expanded(
            child: IndexedStack(
              index: widget.activePage.index,
              children:
                  PageType.values.map((pageType) {
                    return _getPageWidget(pageType);
                  }).toList(),
            ),
          ),
          // Right Sidebar (MeetingScreen일 때만 렌더링)
          if (_showRightSidebar)
            Consumer<FileSystemProvider>(
              builder: (context, fileSystemProvider, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  width: _isRightExpanded ? 250 : 0, // 0으로 하면 완전히 사라집니다.
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      left: BorderSide(color: Colors.grey.shade200),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: const Offset(-1, 0),
                      ),
                    ],
                  ),
                  child: ClipRect(
                    // ClipRect를 사용하여 오버플로우된 콘텐츠를 잘라냅니다.
                    // 또한, _isRightExpanded가 false일 때 RightSidebarContent를 렌더링하지 않도록 하여 불필요한 레이아웃 계산을 방지합니다.
                    child:
                        _isRightExpanded
                            ? RightSidebarContent(
                              isLoading: fileSystemProvider.isLoading,
                              fileSystemEntries:
                                  fileSystemProvider.fileSystemEntries,
                              onEntryTap: (entry) {
                                if (entry.isDirectory) {
                                  debugPrint('폴더는 로드할 수 없습니다: ${entry.name}');
                                  return;
                                }
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
                              sidebarIsExpanded:
                                  _isRightExpanded, // RightSidebarContent로 현재 확장 상태 전달
                            )
                            : const SizedBox.shrink(), // 사이드바가 닫혔을 때는 아무것도 렌더링하지 않습니다.
                  ),
                );
              },
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
