import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart'; // 달력 위젯 라이브러리 임포트
import '../layout/left_sidebar_layout.dart';// 좌측 사이드바 레이아웃 임포트
import '../layout/bottom_section.dart'; // 하단 액션 영역 위젯 임포트


// 달력 페이지 위젯
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

// CalendarPage 위젯의 상태를 관리하는 클래스
class _CalendarPageState extends State<CalendarPage> {
  // 달력에서 현재 포커스된 날짜
  DateTime _focusedDay = DateTime.now();
  // 달력에서 선택된 날짜
  DateTime? _selectedDay;
  // 달력 표시 형식 (월, 2주, 주)
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // 오늘 날짜로 이동하는 함수
  void _goToToday() {
    setState(() {
      _focusedDay = DateTime.now(); // 포커스된 날짜를 오늘로 설정
      _selectedDay = DateTime.now(); // 선택된 날짜를 오늘로 설정
    });
  }

  @override
  Widget build(BuildContext context) {
    return LeftSidebarLayout(
      // 좌측 사이드바 레이아웃 사용
      activePage: PageType.calendar, // 현재 활성화된 페이지 타입을 달력으로 설정
      child: Column(
        // 메인 콘텐츠 영역 구성
        children: [
          _buildTopBar(), // 상단 바 위젯 빌드
          Expanded(child: _buildCalendarView()), // 남은 공간을 달력 뷰로 채움
          // 하단에 Collapse 가능한 액션 영역 위젯 추가
          const CollapsibleBottomSection(),
        ],
      ),
    );
  }

  // 상단 바 위젯: 제목, "2 Weeks" 버튼과 "Today" 버튼 포함 (현재 2 Weeks 버튼 없음)
  Widget _buildTopBar() {
    return Container(
      height: 50,
      color: Colors.grey[300], // 배경색
      padding: const EdgeInsets.symmetric(horizontal: 16), // 좌우 여백
      child: Row(
        // 자식 위젯을 가로로 배치
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // 자식 위젯을 양 끝으로 정렬
        children: [
          // 페이지 제목
          const Text(
            'Calendar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Row(
            // 버튼들을 가로로 배치
            children: [
              // "Today" 버튼
              ElevatedButton(onPressed: _goToToday, child: const Text('Today')),
            ],
          ),
        ],
      ),
    );
  }

  // TableCalendar 위젯을 이용한 달력 뷰 빌드
  Widget _buildCalendarView() {
    return TableCalendar(
      firstDay: DateTime.utc(2010, 1, 1), // 달력에 표시할 첫 번째 날짜
      lastDay: DateTime.utc(2030, 12, 31), // 달력에 표시할 마지막 날짜
      focusedDay: _focusedDay, // 현재 포커스된 날짜
      calendarFormat: _calendarFormat, // 현재 달력 표시 형식
      onFormatChanged: (format) {
        // 달력 형식 변경 시 호출
        setState(() {
          _calendarFormat = format; // 상태 변경 및 위젯 다시 빌드 요청
        });
      },
      // 날짜 선택 여부를 판단하는 함수
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      // 날짜가 선택되었을 때 호출되는 함수
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay; // 선택된 날짜 업데이트
          _focusedDay = focusedDay; // 포커스된 날짜 업데이트
        });
      },
      calendarStyle: const CalendarStyle(
        // 달력 스타일 설정
        todayDecoration: BoxDecoration(
          // 오늘 날짜 디자인
          color: Colors.blue, // 배경색
          shape: BoxShape.circle, // 모양
        ),
        selectedDecoration: BoxDecoration(
          // 선택된 날짜 디자인
          color: Colors.orange, // 배경색
          shape: BoxShape.circle, // 모양
        ),
      ),
    );
  }
}
