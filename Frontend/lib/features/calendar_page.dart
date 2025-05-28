// lib/features/calendar_page.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../layout/main_layout.dart';
import 'page_type.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  void _goToToday() {
    setState(() {
      _focusedDay = DateTime.now();
      _selectedDay = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      // ✅ MainLayout 사용
      activePage: PageType.calendar,
      child: Column(
        children: [
          _buildTopBar(), // ✅ 상단 바
          Expanded(child: _buildCalendarView()), // ✅ 달력 뷰
          // CollapsibleBottomSection 제거
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      // ✅ 수정된 Container
      height: 50,
      // color: Colors.white, // <--- 이 줄 삭제
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white, // <--- color 속성을 BoxDecoration 안으로 이동
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Calendar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          ElevatedButton(
            onPressed: _goToToday, // _goToToday 함수는 그대로 유지
            child: const Text('Today'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3d98f4),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarView() {
    return Padding(
      // ✅ 전체 뷰에 패딩 추가
      padding: const EdgeInsets.all(16.0),
      child: Card(
        // ✅ Card 뷰 적용
        elevation: 3.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0), // ✅ Card 내부에 패딩 추가
          child: TableCalendar(
            firstDay: DateTime.utc(2010, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            headerStyle: const HeaderStyle(
              // ✅ 헤더 스타일
              formatButtonVisible: true,
              titleCentered: true,
              titleTextStyle: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
              ),
              formatButtonTextStyle: TextStyle(color: Colors.white),
              formatButtonDecoration: BoxDecoration(
                color: Color(0xFF3d98f4),
                borderRadius: BorderRadius.all(Radius.circular(12.0)),
              ),
              leftChevronIcon: Icon(
                Icons.chevron_left,
                color: Color(0xFF3d98f4),
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right,
                color: Color(0xFF3d98f4),
              ),
            ),
            calendarStyle: CalendarStyle(
              // ✅ 달력 스타일
              todayDecoration: BoxDecoration(
                color: Colors.deepPurple.shade100, // ✅ 색상 변경
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.deepPurple.shade400, // ✅ 색상 변경
                shape: BoxShape.circle,
              ),
              weekendTextStyle: TextStyle(color: Colors.red.shade400),
              outsideDaysVisible: false, // 해당 월 외 날짜 숨기기
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              // ✅ 요일 스타일
              weekendStyle: TextStyle(
                color: Colors.red.shade600,
                fontWeight: FontWeight.w500,
              ),
              weekdayStyle: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}
