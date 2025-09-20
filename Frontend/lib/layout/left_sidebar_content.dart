// Frontend/lib/layout/left_sidebar_content.dart
import 'package:flutter/material.dart';
import '../features/page_type.dart';
import '../providers/token_status_provider.dart';
import 'package:provider/provider.dart';
import '../auth/login_page.dart';

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
            _buildUserProfileIcon(context),
            _sideBarItem(
              context,
              Icons.settings_outlined,
              '설정',
              PageType.settings,
              () => onPageSelected(PageType.settings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserProfileIcon(BuildContext context) {
    return Consumer<TokenStatusProvider>(
      builder: (context, tokenProvider, child) {
        return PopupMenuButton<String>(
          tooltip: '사용자 프로필',
          offset: const Offset(40, 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          elevation: 8.0,
          color: Theme.of(context).cardColor,
          itemBuilder: (BuildContext context) {
            return _buildUserProfileMenuItems(context, tokenProvider);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Icon(
              Icons.person_outline,
              color: const Color(0xFF475569),
              size: 20,
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
            // ✨ [수정] 고정 너비(width: 200) 속성 제거
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
            ? Theme.of(context).scaffoldBackgroundColor
            : Colors.transparent;

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
