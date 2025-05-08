import 'package:flutter/material.dart';
import 'meeting_screen.dart';
import 'calendar_page.dart';
import 'graph_page.dart';
import 'history.dart';


/// 현재 활성 페이지를 나타내는 열거형
enum PageType { home, calendar, graph, history }

/// 좌측 사이드바만 공통으로 두고, 나머지 영역은 각 페이지(child)가 담당하는 레이아웃
class LeftSidebarLayout extends StatelessWidget {
  final Widget child; // 각 페이지의 메인 콘텐츠
  final PageType activePage; // 현재 활성화된 페이지

  const LeftSidebarLayout({
    super.key,
    required this.child,
    required this.activePage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [_buildSideBar(context), Expanded(child: child)]),
    );
  }

  // 좌측 사이드바 (아이콘을 통해 페이지 전환, 현재 활성 페이지의 아이콘는 표시하지 않음)
  Widget _buildSideBar(BuildContext context) {
    return Container(
      width: 60,
      color: Colors.grey[200],
      child: Column(
        children: [
          const SizedBox(height: 40),
          if (activePage != PageType.home)
            _sideBarIcon(
              Icons.home,
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const MeetingScreen()),
              ),
            ),
          if (activePage != PageType.calendar)
            _sideBarIcon(
              Icons.calendar_today,
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const CalendarPage()),
              ),
            ),
          if (activePage != PageType.graph)
            _sideBarIcon(
              Icons.show_chart,
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const GraphPage()),
              ),
            ),
          _sideBarIcon(Icons.search_rounded, () => print('검색')),
          _sideBarIcon(
            Icons.history,
            () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HistoryPage()),
              ),
            ),
        ],
      ),
    );
  }

  // 개별 아이콘 버튼
  Widget _sideBarIcon(IconData icon, VoidCallback onPressed) {
    return IconButton(icon: Icon(icon), onPressed: onPressed);
  }
}
