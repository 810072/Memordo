// Frontend/lib/layout/left_sidebar_content.dart
import 'package:flutter/material.dart';
import '../features/meeting_screen.dart'; // MeetingScreen은 이제 IndexedStack의 자식으로 직접 사용
import '../features/calendar_page.dart';
import '../features/graph_page.dart';
import '../features/history.dart';
import '../auth/login_page.dart';
import '../features/page_type.dart';
import '../features/settings_page.dart';
import 'package:provider/provider.dart'; // Provider 임포트
import '../providers/token_status_provider.dart'; // TokenStatusProvider 임포트

class LeftSidebarContent extends StatelessWidget {
  final bool isExpanded;
  final PageType activePage;
  final ValueChanged<PageType> onPageSelected; // 추가: 페이지 선택 콜백

  const LeftSidebarContent({
    Key? key,
    required this.isExpanded,
    required this.activePage,
    required this.onPageSelected, // 생성자로 콜백 받기
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
              () => onPageSelected(PageType.home), // 콜백 호출
            ),
            _sideBarItem(
              context,
              Icons.history_outlined,
              '방문 기록',
              PageType.history,
              () => onPageSelected(PageType.history), // 콜백 호출
            ),
            _sideBarItem(
              context,
              Icons.calendar_today_outlined,
              '달력',
              PageType.calendar,
              () => onPageSelected(PageType.calendar), // 콜백 호출
            ),
            _sideBarItem(
              context,
              Icons.show_chart_outlined,
              '그래프',
              PageType.graph,
              () => onPageSelected(PageType.graph), // 콜백 호출
            ),
            _sideBarItem(
              context,
              Icons.search_outlined,
              '검색',
              PageType.home, // PageType.home으로 설정되어 MeetingScreen에서 비활성화됩니다.
              null, // onPressed를 null로 전달
              tooltipMessage: '검색 기능은 추후 추가 예정입니다.',
            ),
            const Spacer(),
            _sideBarItem(
              context,
              Icons.settings_outlined,
              'Settings',
              PageType.settings,
              () => onPageSelected(PageType.settings), // 콜백 호출
            ),
            _sideBarItem(
              context,
              Icons.logout_outlined,
              '로그아웃',
              PageType.home, // 이 버튼은 페이지 이동이 아니라 특정 액션입니다.
              // 따라서 isCurrentPage와 상관없이 항상 활성화되어야 합니다.
              () async {
                // 로그아웃 시 TokenStatusProvider를 통해 토큰 삭제 및 로그인 페이지로 이동
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
    VoidCallback? onPressed, { // onPressed를 Nullable로 변경
    bool alwaysEnabled = false, // 새로 추가된 속성: 항상 활성화될지 여부
    String? tooltipMessage, // 새로 추가된 툴팁 메시지
  }) {
    // 현재 activePage와 pageType이 일치하는지 확인
    final bool isCurrentPage = activePage == pageType;
    // 버튼의 활성화 여부를 결정합니다. alwaysEnabled가 true이거나, 현재 페이지가 아닐 때 활성화.
    final bool isEnabled = alwaysEnabled || !isCurrentPage;

    final Color activeColor = const Color(0xFF3d98f4);
    final Color inactiveColor = const Color(0xFF475569);
    final Color textColor =
        isCurrentPage && !alwaysEnabled ? activeColor : inactiveColor;
    final Color iconColor =
        isEnabled ? textColor : Colors.grey.shade400; // 비활성화 시 아이콘 색상
    final Color bgColor =
        isCurrentPage && !alwaysEnabled
            ? const Color(0xFFF1F5F9)
            : Colors.white;

    // 툴팁 메시지를 우선적으로 사용하고, 없으면 text를 사용합니다.
    final String resolvedTooltip = tooltipMessage ?? text;

    return Tooltip(
      message: isExpanded ? '' : resolvedTooltip, // 확장 시에는 툴팁 없음
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
            onTap:
                isEnabled ? onPressed : null, // isEnabled가 false이면 onTap은 null
            borderRadius: BorderRadius.circular(8.0),
            hoverColor: const Color(0xFFE2E8F0), // Slate-200
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: 12.0,
                horizontal: isExpanded ? 12.0 : 0.0, // 확장에 따라 수평 패딩 조정
              ),
              child: Row(
                mainAxisAlignment:
                    isExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                children: [
                  // Icon을 Flexible로 감싸주세요
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
