// lib/layout/left_sidebar_content.dart
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import '../features/page_type.dart';
import '../providers/token_status_provider.dart';
import 'package:provider/provider.dart';
import '../auth/auth_dialog.dart';

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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent, // 변경 없음
      child: Column(
        // ✨ [수정] 전체를 Column으로 감싸기
        children: [
          // ✨ [추가] 상단 아이콘 영역
          Container(
            height: 39,
            width: double.infinity, // 너비 채우기
            // color: Colors.blue.withOpacity(0.1), // 영역 확인용 임시 배경색
            padding: const EdgeInsets.all(8.0), // 아이콘 주변 여백
            child: Center(
              // 아이콘을 가운데 정렬
              child: Image.asset(
                'assets/app_icon.png', // <<< 앱 아이콘 경로 (실제 경로로 수정 필요)
                fit: BoxFit.contain, // 비율 유지하며 채우기
                height: 35, // 아이콘 높이 조절 (40보다 작게)
              ),
            ),
          ),
          // ✨ [추가] 구분선
          Divider(
            height: 1, // 구분선 높이
            thickness: 1, // 구분선 두께
            color: Theme.of(context).dividerColor, // 테마 색상 사용
          ),
          // ✨ [수정] 기존 내용을 Expanded로 감싸 남은 공간 채우기
          Expanded(
            child: Container(
              padding: EdgeInsets.zero, // 기존 패딩은 유지
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                    Icons.lan_outlined,
                    '그래프',
                    PageType.graph,
                    () => onPageSelected(PageType.graph),
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
                    Icons.search_outlined,
                    '검색',
                    PageType.search,
                    () => onPageSelected(PageType.search),
                  ),
                  // _sideBarItem(
                  //   context,
                  //   Icons.forum_outlined,
                  //   '챗봇',
                  //   null,
                  //   _openChatbotWindow,
                  //   alwaysEnabled: true,
                  // ),
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
          ),
        ],
      ),
    );
  }

  // _buildUserProfileIcon, _buildUserProfileMenuItems, _sideBarItem 메서드는 변경 없음
  // ... (기존 메서드 코드) ...
  Widget _buildUserProfileIcon(BuildContext context) {
    return Consumer<TokenStatusProvider>(
      builder: (context, tokenProvider, child) {
        return PopupMenuButton<String>(
          tooltip: '사용자 프로필',
          padding: EdgeInsets.zero,
          offset: const Offset(50, 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          elevation: 8.0,
          color: Theme.of(context).cardColor,
          itemBuilder: (BuildContext context) {
            return _buildUserProfileMenuItems(context, tokenProvider);
          },
          child: Container(
            height: 48,
            width: 50,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.transparent, width: 2),
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.person_outline,
                color: Color(0xFF475569),
                size: 24,
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
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      barrierDismissible: false, // ✨ [추가]
                      builder: (BuildContext context) {
                        return const AuthDialog();
                      },
                    ).then((_) {
                      context.read<TokenStatusProvider>().loadStatus(context);
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
    PageType? pageType,
    VoidCallback? onPressed, {
    bool alwaysEnabled = false,
    String? tooltipMessage,
  }) {
    final bool isCurrentPage = pageType != null && activePage == pageType;
    final bool isEnabled = alwaysEnabled || !isCurrentPage;

    final Color activeColor = const Color(0xFF3d98f4);
    final Color inactiveColor = const Color(0xFF475569);
    final Color iconColor = isCurrentPage ? activeColor : inactiveColor;

    return Tooltip(
      message: tooltipMessage ?? text,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        height: 48,
        width: 50,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isCurrentPage ? activeColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          child: Center(child: Icon(icon, color: iconColor, size: 22)),
        ),
      ),
    );
  }
}
