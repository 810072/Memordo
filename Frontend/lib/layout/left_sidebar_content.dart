// lib/layout/left_sidebar_content.dart
import 'package:flutter/material.dart';
import '../features/meeting_screen.dart';
import '../features/calendar_page.dart';
import '../features/graph_page.dart';
import '../features/history.dart';
import '../auth/login_page.dart';
import '../features/page_type.dart';

class LeftSidebarContent extends StatelessWidget {
  final bool isExpanded;
  final PageType activePage;

  const LeftSidebarContent({
    Key? key,
    required this.isExpanded,
    required this.activePage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: 10.0,
          horizontal: isExpanded ? 3.0 : 5.0,
        ),
        child: Column(
          crossAxisAlignment:
              isExpanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.only(
                  left: 16.0,
                  bottom: 20.0,
                  top: 4.0,
                ),
                child: Text(
                  'Features',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                    fontFamily: 'Work Sans',
                  ),
                ),
              ),
            _sideBarItem(
              context,
              Icons.description_outlined,
              '메모 작성',
              PageType.home,
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const MeetingScreen()),
              ),
            ),
            _sideBarItem(
              context,
              Icons.history_outlined,
              '방문 기록',
              PageType.history,
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HistoryPage()),
              ),
            ),
            _sideBarItem(
              context,
              Icons.calendar_today_outlined,
              '달력',
              PageType.calendar,
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const CalendarPage()),
              ),
            ),
            _sideBarItem(
              context,
              Icons.show_chart_outlined,
              '그래프',
              PageType.graph,
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const GraphPage()),
              ),
            ),
            _sideBarItem(
              context,
              Icons.search_outlined,
              '검색',
              PageType.home, // Add a Search page later
              () => print('검색'),
              isActiveOverride: true,
            ),
            const Spacer(),
            _sideBarItem(
              context,
              Icons.settings_outlined,
              'Settings',
              PageType.home, // Add a Settings page later
              () => print('Settings'),
              isActiveOverride: true,
            ),
            _sideBarItem(
              context,
              Icons.logout_outlined,
              '로그아웃',
              PageType.home,
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => LoginPage()),
              ),
              isActiveOverride: true,
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _sideBarItem(
    BuildContext context,
    IconData icon,
    String text,
    PageType pageType,
    VoidCallback onPressed, {
    bool isActiveOverride = false,
  }) {
    final bool isCurrentPage = activePage == pageType && !isActiveOverride;
    final Color activeColor = const Color(0xFF3d98f4);
    final Color inactiveColor = const Color(0xFF475569);
    final Color textColor = isCurrentPage ? activeColor : inactiveColor;
    final Color bgColor =
        isCurrentPage
            ? const Color(0xFFF1F5F9)
            : Colors.white; // Slate-100 or White

    return Tooltip(
      message: isExpanded ? '' : text, // Show tooltip only when collapsed
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isCurrentPage ? null : onPressed,
            borderRadius: BorderRadius.circular(8.0),
            hoverColor: const Color(0xFFE2E8F0), // Slate-200
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: 12.0,
              ),
              child: Row(
                mainAxisAlignment:
                    isExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                children: [
                  Icon(icon, color: textColor, size: 20),
                  if (isExpanded) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Work Sans',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
