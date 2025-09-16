// lib/viewmodels/calendar_viewmodel.dart
import 'package:flutter/material.dart';

class CalendarViewModel with ChangeNotifier {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  DateTime get focusedDay => _focusedDay;
  DateTime? get selectedDay => _selectedDay;

  /// 사용자가 특정 날짜를 선택했을 때 호출됩니다.
  void onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    // 이미 선택된 날짜를 다시 탭한 경우, 아무 작업도 하지 않습니다.
    if (_selectedDay != selectedDay) {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
      notifyListeners();
    }
  }

  /// 포커스된 날짜를 변경합니다. (예: 월 이동)
  void setFocusedDay(DateTime day) {
    if (_focusedDay != day) {
      _focusedDay = day;
      notifyListeners();
    }
  }

  /// 'Today' 버튼을 눌렀을 때 호출됩니다.
  void jumpToToday() {
    _focusedDay = DateTime.now();
    _selectedDay = null; // 오늘로 이동할 때는 선택된 날짜를 해제합니다.
    notifyListeners();
  }
}
