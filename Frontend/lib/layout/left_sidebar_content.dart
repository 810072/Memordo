// Frontend/lib/layout/left_sidebar_content.dart
import 'package:flutter/material.dart';
import '../features/meeting_screen.dart';
import '../features/calendar_page.dart';
import '../features/graph_page.dart';
import '../features/history.dart';
import '../features/search_page.dart'; // ✨ 추가
import '../auth/login_page.dart';
import '../features/page_type.dart';
import '../features/settings_page.dart';
import 'package:provider/provider.dart';
import '../providers/token_status_provider.dart';

class LeftSidebarContent extends StatelessWidget {
  final bool isExpanded;
  final PageType activePage;
  final ValueChanged<PageType> onPageSelected;

  const LeftSidebarContent({
    Key? key,
    required this.isExpanded,
    required this.activePage,
    required this.onPageSelected,
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
              () => onPageSelected(PageType.home),
            ),
            _sideBarItem(
              context,
              Icons.history_outlined,
              '방문 기록',
              PageType.history,
              () => onPageSelected(PageType.history),
            ),
            _sideBarItem(
              context,
              Icons.calendar_today_outlined,
              '달력',
              PageType.calendar,
              () => onPageSelected(PageType.calendar),
            ),
            _sideBarItem(
              context,
              Icons.show_chart_outlined,
              '그래프',
              PageType.graph,
              () => onPageSelected(PageType.graph),
            ),
            _sideBarItem(
              context,
              Icons.search_outlined,
              '검색',
              PageType.search, // ✨ 변경: PageType.search
              () => onPageSelected(PageType.search), // ✨ 변경: SearchPage로 이동
              // tooltipMessage: '검색 기능은 추후 추가 예정입니다.', // 툴팁 메시지 제거
            ),
            const Spacer(),
            _sideBarItem(
              context,
              Icons.settings_outlined,
              'Settings',
              PageType.settings,
              () => onPageSelected(PageType.settings),
            ),
            _sideBarItem(
              context,
              Icons.logout_outlined,
              '로그아웃',
              PageType.home,
              () async {
                await Provider.of<TokenStatusProvider>(
                  context,
                  listen: false,
                ).forceLogout(context);
              },
              alwaysEnabled: true,
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
    VoidCallback? onPressed, {
    bool alwaysEnabled = false,
    String? tooltipMessage,
  }) {
    final bool isCurrentPage = activePage == pageType;
    final bool isEnabled = alwaysEnabled || !isCurrentPage;

    final Color activeColor = const Color(0xFF3d98f4);
    final Color inactiveColor = const Color(0xFF475569);
    final Color textColor =
        isCurrentPage && !alwaysEnabled ? activeColor : inactiveColor;
    final Color iconColor = isEnabled ? textColor : Colors.grey.shade400;
    final Color bgColor =
        isCurrentPage && !alwaysEnabled
            ? const Color(0xFFF1F5F9)
            : Colors.white;

    final String resolvedTooltip = tooltipMessage ?? text;

    return Tooltip(
      message: isExpanded ? '' : resolvedTooltip,
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
            onTap: isEnabled ? onPressed : null,
            borderRadius: BorderRadius.circular(8.0),
            hoverColor: const Color(0xFFE2E8F0),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: isExpanded ? 12.0 : 0.0,
              ),
              child: Row(
                mainAxisAlignment:
                    isExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                children: [
                  Flexible(child: Icon(icon, color: iconColor, size: 20)),
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
