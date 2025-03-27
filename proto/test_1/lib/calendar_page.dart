import 'package:flutter/material.dart';
import 'meeting_screen.dart'; // 메인화면 재이동을 위해 import
import 'graph_page.dart'; // 그래프페이지 이동도 가능하게 import

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSideBar(context),
          // 달력 메인 영역
          Expanded(
            child: Column(
              children: [
                _buildTopBar(), // 상단 "2025 / 03"
                Expanded(child: _buildCalendarTable()), // 달력
                _buildBottomArea(), // 하단 버튼 / AI 영역
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 좌측 사이드바 (중복)
  Widget _buildSideBar(BuildContext context) {
    return Container(
      width: 200,
      color: Colors.grey[200],
      child: Column(
        children: [
          const SizedBox(height: 40),
          // 홈(MeetingScreen)으로 돌아가기
          _sideBarIcon(Icons.home, () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MeetingScreen()),
            );
          }),
          // 그래프 페이지로 이동
          _sideBarIcon(Icons.show_chart, () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const GraphPage()),
            );
          }),
          // 검색 아이콘
          _sideBarIcon(Icons.search_rounded, () => print('검색 클릭')),
          // 히스토리 아이콘
          _sideBarIcon(Icons.history, () => print('히스토리 클릭')),
        ],
      ),
    );
  }

  Widget _sideBarIcon(IconData icon, VoidCallback onPressed) {
    return IconButton(icon: Icon(icon), onPressed: onPressed);
  }

  // 상단 바
  Widget _buildTopBar() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Text(
        '2025 / 03',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  // 달력 테이블
  Widget _buildCalendarTable() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Table(
        border: TableBorder.all(color: Colors.grey),
        children: [
          // 첫 행: 요일 헤더
          TableRow(
            children: [
              _dayCell('일', header: true),
              _dayCell('월', header: true),
              _dayCell('화', header: true),
              _dayCell('수', header: true),
              _dayCell('목', header: true),
              _dayCell('금', header: true),
              _dayCell('토', header: true),
            ],
          ),
          // 이하 예시
          _buildDayRow(['', '', '', '', '', '', '1']),
          _buildDayRow(['2', '3', '4', '5', '6', '7', '8']),
          _buildDayRow(['9', '10', '11', '12', '13', '14', '15']),
          _buildDayRow(['16', '17', '18', '19', '20', '21', '22']),
          _buildDayRow(['23', '24', '25', '26', '27', '28', '29']),
          _buildDayRow(['30', '31', '', '', '', '', '']),
        ],
      ),
    );
  }

  TableRow _buildDayRow(List<String> days) {
    return TableRow(children: days.map((day) => _dayCell(day)).toList());
  }

  Widget _dayCell(String text, {bool header = false}) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      color: header ? Colors.grey[200] : Colors.white,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: header ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // 하단 버튼 및 AI 영역
  Widget _buildBottomArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ElevatedButton(onPressed: () {}, child: const Text('내용 요약')),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: () {}, child: const Text('태그 추출')),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: () {}, child: const Text('검색')),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'AI 요약 내용...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.bottomRight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(120, 40)),
              onPressed: () {},
              child: const Text('적용'),
            ),
          ),
        ],
      ),
    );
  }
}
