// Frontend/lib/layout/left_sidebar_content.dart
import 'package:flutter/material.dart';
import '../features/page_type.dart';
import '../providers/token_status_provider.dart';
import 'package:provider/provider.dart';

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
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: 0.0,
          horizontal: isExpanded ? 3.0 : 5.0,
        ),
        child: Column(
          crossAxisAlignment:
              isExpanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
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
              PageType.search,
              () => onPageSelected(PageType.search),
            ),
            const Spacer(),
            _sideBarItem(
              context,
              Icons.settings_outlined,
              '설정',
              PageType.settings,
              () => onPageSelected(PageType.settings),
            ),
            // _sideBarItem(
            //   context,
            //   Icons.logout_outlined,
            //   '로그아웃',
            //   PageType.home,
            //   () async {
            //     await Provider.of<TokenStatusProvider>(
            //       context,
            //       listen: false,
            //     ).forceLogout(context);
            //   },
            //   alwaysEnabled: true,
            // ), 사용자 프로필 기능추가로인한 로그아웃 기능 주석 처리
            // const SizedBox(height: 5),
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

    // ✨ [수정] 활성화된 아이템의 배경색을 scaffoldBackgroundColor(흰색)로 변경
    final Color bgColor =
        isCurrentPage && !alwaysEnabled
            ? Theme.of(context).scaffoldBackgroundColor
            : Colors.transparent; // 비활성 아이템은 배경색 없음

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
            // ✨ [수정] hoverColor를 좀 더 연하게 조정
            hoverColor: Colors.black.withOpacity(0.04),
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
