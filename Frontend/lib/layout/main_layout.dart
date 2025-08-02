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

  // ============== 챗봇 창을 여는 함수 추가 ==============
  void _openChatbotWindow() async {
    final window = await DesktopMultiWindow.createWindow(
      jsonEncode({'arg1': 'value1', 'arg2': 'value2'}),
    );
    window
      ..setFrame(const Offset(100, 100) & const Size(560, 960)) // 창 크기 및 위치 설정
      ..center()
      ..setTitle('Memordo 챗봇') // 창 제목 설정
      ..show();
  }
  // =======================================================

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
      backgroundColor: const Color(0xFFF1F5F9),
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
          // ============== 챗봇 아이콘 버튼 추가 ==============
          IconButton(
            icon: const Icon(
              Icons.smart_toy_outlined,
              color: Color(0xFF475569),
            ),
            onPressed: _openChatbotWindow,
            tooltip: '챗봇 열기',
          ),
          const SizedBox(width: 4), // 버튼 사이 간격 추가
          // =================================================
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            // ✨ 왼쪽 사이드바 크기 수정 (기존: 240 -> 192, 65 -> 52)
            width: _isLeftExpanded ? 192 : 52,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
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
              children:
                  PageType.values.map((pageType) {
                    return _getPageWidget(pageType);
                  }).toList(),
            ),
          ),
          if (_showRightSidebar)
            Consumer<FileSystemProvider>(
              builder: (context, fileSystemProvider, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  // ✨ 오른쪽 사이드바 크기 수정 (기존: 250 -> 200)
                  width: _isRightExpanded ? 200 : 0,
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
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: ClipRect(
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
                              sidebarIsExpanded: _isRightExpanded,
                            )
                            : const SizedBox.shrink(),
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
