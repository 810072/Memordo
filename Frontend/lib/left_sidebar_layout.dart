import 'package:flutter/material.dart';
import 'meeting_screen.dart'; // 미팅 화면 임포트
import 'calendar_page.dart'; // 달력 페이지 임포트
import 'graph_page.dart'; // 그래프 페이지 임포트

/// 현재 활성 페이지를 나타내는 열거형 정의
enum PageType { home, calendar, graph }

/// 좌측 사이드바만 공통으로 두고, 나머지 영역은 각 페이지(child)가 담당하는 레이아웃 위젯
class LeftSidebarLayout extends StatelessWidget {
  final Widget child; // 각 페이지의 메인 콘텐츠를 표시할 위젯
  final PageType activePage; // 현재 활성화된 페이지 타입

  // 생성자
  const LeftSidebarLayout({
    super.key,
    required this.child, // 메인 콘텐츠 위젯은 필수
    required this.activePage, // 활성 페이지 타입은 필수
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 기본적인 앱 화면 구조 제공
      body: Row(
        // 좌측 사이드바와 메인 콘텐츠 영역을 가로로 배치
        children: [
          _buildSideBar(context), // 좌측 사이드바 위젯 빌드
          Expanded(child: child), // 남은 공간을 자식 위젯(각 페이지의 메인 콘텐츠)으로 채움
        ],
      ),
    );
  }

  // 좌측 사이드바 위젯 (아이콘을 통해 페이지 전환, 현재 활성 페이지의 아이콘는 표시하지 않음)
  Widget _buildSideBar(BuildContext context) {
    return Container(
      width: 60, // 사이드바 너비
      color: Colors.grey[200], // 배경색
      child: Column(
        // 아이콘들을 세로로 배치
        children: [
          const SizedBox(height: 40), // 상단 여백
          // 홈 아이콘: 현재 페이지가 홈이 아니면 표시하고 탭 시 MeetingScreen으로 이동
          if (activePage != PageType.home)
            _sideBarIcon(
              Icons.home,
              () => Navigator.pushReplacement(
                // 현재 페이지를 교체 (뒤로가기 시 이전 페이지로 돌아가지 않음)
                context,
                MaterialPageRoute(builder: (_) => const MeetingScreen()),
              ),
            ),
          // 달력 아이콘: 현재 페이지가 달력이 아니면 표시하고 탭 시 CalendarPage로 이동
          if (activePage != PageType.calendar)
            _sideBarIcon(
              Icons.calendar_today,
              () => Navigator.pushReplacement(
                // 현재 페이지를 교체
                context,
                MaterialPageRoute(builder: (_) => const CalendarPage()),
              ),
            ),
          // 그래프 아이콘: 현재 페이지가 그래프가 아니면 표시하고 탭 시 GraphPage로 이동
          if (activePage != PageType.graph)
            _sideBarIcon(
              Icons.show_chart,
              () => Navigator.pushReplacement(
                // 현재 페이지를 교체
                context,
                MaterialPageRoute(builder: (_) => const GraphPage()),
              ),
            ),
          // 검색 아이콘 (현재 기능 없음)
          _sideBarIcon(Icons.search_rounded, () => print('검색')),
          // 히스토리 아이콘 (현재 기능 없음)
          _sideBarIcon(Icons.history, () => print('히스토리')),
        ],
      ),
    );
  }

  // 개별 사이드바 아이콘 버튼 위젯
  Widget _sideBarIcon(IconData icon, VoidCallback onPressed) {
    return IconButton(
      // 아이콘 형태의 버튼
      icon: Icon(icon), // 아이콘 지정
      onPressed: onPressed, // 버튼 클릭 시 실행될 콜백 함수
    );
  }
}
