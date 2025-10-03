// lib/viewmodels/calendar_viewmodel.dart
import 'package:flutter/material.dart';

class CalendarViewModel with ChangeNotifier {
  DateTime _focusedDay = DateTime.now();
  // ✨ [수정] selectedDay가 null을 허용하지 않고, 기본값으로 오늘 날짜를 갖도록 변경합니다.
  DateTime _selectedDay = DateTime.now();

  DateTime get focusedDay => _focusedDay;
  DateTime get selectedDay => _selectedDay;

  /// 사용자가 특정 날짜를 선택했을 때 호출됩니다.
  void onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    // 이미 선택된 날짜를 다시 탭한 경우, 아무 작업도 하지 않습니다.
    if (!isSameDay(_selectedDay, selectedDay)) {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
      notifyListeners();
    }
  }

  /// 포커스된 날짜를 변경합니다. (예: 월 이동)
  void setFocusedDay(DateTime day) {
    if (!isSameDay(_focusedDay, day)) {
      _focusedDay = day;
      notifyListeners();
    }
  }

  /// 'Today' 버튼을 눌렀을 때 호출됩니다.
  void jumpToToday() {
    final now = DateTime.now();
    _focusedDay = now;
    // ✨ [수정] 선택된 날짜도 오늘로 변경합니다.
    _selectedDay = now;
    notifyListeners();
  }

  // isSameDay 헬퍼 함수 추가 (TableCalendar 위젯의 것과 동일한 로직)
  bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) {
      return false;
    }
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
