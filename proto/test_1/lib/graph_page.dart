import 'package:flutter/material.dart';
import 'meeting_screen.dart';
import 'calendar_page.dart';

class GraphPage extends StatelessWidget {
  const GraphPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSideBar(context),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildGraphArea()),
                _buildBottomArea(),
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
          // 메인화면으로
          _sideBarIcon(Icons.home, () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MeetingScreen()),
            );
          }),
          // 달력 페이지로
          _sideBarIcon(Icons.calendar_today, () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const CalendarPage()),
            );
          }),
          _sideBarIcon(Icons.search_rounded, () => print('검색 클릭')),
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

  // 그래프 영역
  Widget _buildGraphArea() {
    return Center(
      child: SizedBox(
        width: 300,
        height: 200,
        child: CustomPaint(painter: _GraphPainter()),
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

// 간단히 원+선 그래프를 그리는 예시
class _GraphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLine =
        Paint()
          ..color = Colors.grey
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    final paintCircle =
        Paint()
          ..color = Colors.grey
          ..style = PaintingStyle.fill;

    final points = [
      Offset(size.width * 0.1, size.height * 0.5),
      Offset(size.width * 0.4, size.height * 0.2),
      Offset(size.width * 0.6, size.height * 0.6),
      Offset(size.width * 0.9, size.height * 0.4),
    ];

    // 선 연결
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paintLine);
    }

    // 원(노드) 표시
    for (final p in points) {
      canvas.drawCircle(p, 10, paintCircle);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
