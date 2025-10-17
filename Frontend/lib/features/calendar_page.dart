// lib/features/calendar_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../viewmodels/calendar_viewmodel.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;

  final Map<DateTime, String> _memoData = {};

  // 인라인 편집을 위한 상태 변수들
  DateTime? _editingDay;
  final TextEditingController _inlineMemoController = TextEditingController();
  final FocusNode _inlineFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();

    // 포커스가 해제될 때 편집 종료
    _inlineFocusNode.addListener(() {
      if (!_inlineFocusNode.hasFocus && _editingDay != null) {
        _finishEditing();
      }
    });
  }

  @override
  void dispose() {
    _inlineMemoController.dispose();
    _inlineFocusNode.dispose();
    super.dispose();
  }

  DateTime _pureDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  void _saveMemo(DateTime date, String text) {
    setState(() {
      if (text.trim().isEmpty) {
        _memoData.remove(date);
      } else {
        _memoData[date] = text.trim();
      }
    });
    _saveToPrefs();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stringMap = _memoData.map(
      (key, value) => MapEntry(key.toIso8601String(), value),
    );
    await prefs.setString('memoData', jsonEncode(stringMap));
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('memoData');
    if (jsonString != null) {
      final Map<String, dynamic> decoded = jsonDecode(jsonString);
      setState(() {
        _memoData.clear();
        decoded.forEach((key, value) {
          _memoData[DateTime.parse(key)] = value;
        });
      });
    }
  }

  // 더블 클릭 시 편집 모드 시작
  void _startEditing(DateTime day) {
    final pureDay = _pureDate(day);
    setState(() {
      _editingDay = pureDay;
      _inlineMemoController.text = _memoData[pureDay] ?? '';
    });

    // 다음 프레임에서 포커스 요청
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inlineFocusNode.requestFocus();
    });
  }

  // 편집 종료 및 저장
  void _finishEditing() {
    if (_editingDay != null) {
      _saveMemo(_editingDay!, _inlineMemoController.text);
      setState(() {
        _editingDay = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final calendarViewModel = context.watch<CalendarViewModel>();

    return _buildCalendarWithMemo(calendarViewModel);
  }

  Widget _buildCalendarWithMemo(CalendarViewModel viewModel) {
    return SingleChildScrollView(child: _buildCalendarView(viewModel));
  }

  Widget _buildCalendarView(CalendarViewModel viewModel) {
    return TableCalendar(
      locale: 'ko_KR',
      firstDay: DateTime.utc(2010, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: viewModel.focusedDay,
      calendarFormat: _calendarFormat,
      selectedDayPredicate: (day) => isSameDay(viewModel.selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        // 다른 날짜를 클릭하면 진행 중인 편집 종료
        if (_editingDay != null) {
          _finishEditing();
        }
        viewModel.onDaySelected(selectedDay, focusedDay);
      },
      onPageChanged: (focusedDay) {
        // 월 변경 시 편집 종료
        if (_editingDay != null) {
          _finishEditing();
        }
        viewModel.setFocusedDay(focusedDay);
      },
      eventLoader: (day) {
        final pure = _pureDate(day);
        final List<String> events = [];
        if (_memoData.containsKey(pure) && _memoData[pure]!.isNotEmpty) {
          events.add('memo');
        }
        return events;
      },
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, focusedDay) {
          return _buildDayCell(day, false, false);
        },
        selectedBuilder: (context, day, focusedDay) {
          return _buildDayCell(day, true, false);
        },
        todayBuilder: (context, day, focusedDay) {
          return _buildDayCell(day, false, true);
        },
        outsideBuilder: (context, day, focusedDay) {
          return _buildDayCell(day, false, false, isOutside: true);
        },
        markerBuilder: (context, date, events) {
          // 마커는 셀 내부에서 직접 처리하므로 여기서는 빈 위젯 반환
          return const SizedBox.shrink();
        },
      ),
      onFormatChanged: (format) {
        setState(() {
          _calendarFormat = format;
        });
      },
      headerStyle: const HeaderStyle(
        formatButtonVisible: true,
        titleCentered: true,
      ),
      daysOfWeekHeight: 40,
      rowHeight: 120,
    );
  }

  // 커스텀 날짜 셀 빌더
  Widget _buildDayCell(
    DateTime day,
    bool isSelected,
    bool isToday, {
    bool isOutside = false,
  }) {
    final pureDay = _pureDate(day);
    final isEditing = _editingDay != null && isSameDay(_editingDay, day);
    final hasMemo =
        _memoData.containsKey(pureDay) && _memoData[pureDay]!.isNotEmpty;

    // 편집 모드일 때
    if (isEditing) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.blue.shade600, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 날짜 표시
            Container(
              padding: const EdgeInsets.all(4.0),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isToday ? Colors.orange : Colors.black,
                ),
              ),
            ),
            // 인라인 텍스트 필드
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 2.0,
                ),
                child: TextField(
                  controller: _inlineMemoController,
                  focusNode: _inlineFocusNode,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) {
                    _finishEditing();
                  },
                  onTapOutside: (_) {
                    _finishEditing();
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 일반 모드일 때
    return GestureDetector(
      onDoubleTap:
          isOutside
              ? null
              : () {
                _startEditing(day);
              },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color:
              isOutside
                  ? Colors.grey.shade50
                  : isSelected
                  ? Colors.blue.shade50
                  : isToday
                  ? Colors.orange.shade50
                  : Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 날짜 표시
            Container(
              padding: const EdgeInsets.all(4.0),
              child: Row(
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color:
                          isOutside
                              ? Colors.grey.shade400
                              : isToday
                              ? Colors.orange
                              : isSelected
                              ? Colors.blue
                              : Colors.black,
                    ),
                  ),
                  if (hasMemo) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 메모 미리보기
            if (hasMemo)
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.0,
                    vertical: 2.0,
                  ),
                  child: Text(
                    _memoData[pureDay]!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isOutside ? Colors.grey.shade400 : Colors.black87,
                      height: 1.3,
                    ),
                    overflow: TextOverflow.fade,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
