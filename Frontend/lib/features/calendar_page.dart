// lib/features/calendar_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../viewmodels/calendar_viewmodel.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;

  final Map<DateTime, String> _memoData = {};
  final TextEditingController _memoController = TextEditingController();

  // ✨ [삭제] 수정된 파일 데이터를 관리하던 변수 삭제
  // final Map<DateTime, List<String>> _createdFilesData = {};

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
    // ✨ [삭제] 수정된 파일 데이터를 불러오던 함수 호출 삭제
    // _loadCreatedFilesData();
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  DateTime _pureDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  void _saveMemo(DateTime date, String text) {
    setState(() {
      _memoData[date] = text.trim();
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

  // ✨ [삭제] 수정된 파일 데이터를 불러오는 관련 메서드들 전체 삭제
  // Future<void> _loadCreatedFilesData() async { ... }
  // Future<String> _getNotesDirectory() async { ... }
  // Future<List<File>> _getAllMarkdownFiles(Directory dir) async { ... }

  @override
  Widget build(BuildContext context) {
    final calendarViewModel = context.watch<CalendarViewModel>();

    return _buildCalendarWithMemo(calendarViewModel);
  }

  Widget _buildCalendarWithMemo(CalendarViewModel viewModel) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16.0),
            child: _buildCalendarView(viewModel),
          ),
          const SizedBox(height: 24),
          if (viewModel.selectedDay != null) ...[
            // ✨ [삭제] 수정된 파일 목록을 보여주는 위젯 호출 삭제
            // _buildCreatedFilesList(viewModel.selectedDay!),
            // const SizedBox(height: 16),
            _buildMemoSection(viewModel.selectedDay!),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendarView(CalendarViewModel viewModel) {
    return TableCalendar(
      firstDay: DateTime.utc(2010, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: viewModel.focusedDay,
      calendarFormat: _calendarFormat,
      selectedDayPredicate: (day) => isSameDay(viewModel.selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        viewModel.onDaySelected(selectedDay, focusedDay);
        _memoController.text = _memoData[_pureDate(selectedDay)] ?? '';
      },
      onPageChanged: (focusedDay) {
        viewModel.setFocusedDay(focusedDay);
      },
      eventLoader: (day) {
        final pure = _pureDate(day);
        final List<String> events = [];
        if (_memoData.containsKey(pure) && _memoData[pure]!.isNotEmpty) {
          events.add('memo');
        }
        // ✨ [삭제] 파일 이벤트 추가 로직 삭제
        // if (_createdFilesData.containsKey(pure)) {
        //   events.add('file');
        // }
        return events;
      },
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          if (events.isEmpty) return const SizedBox.shrink();

          return Positioned(
            bottom: 4.0,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children:
                  events.map((event) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2.0),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        // ✨ [수정] 파일 마커(파란색) 관련 로직 삭제
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    );
                  }).toList(),
            ),
          );
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
    );
  }

  Widget _buildMemoSection(DateTime selectedDay) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "일일 메모",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _memoController,
                maxLines: 8,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: "메모를 작성하세요.",
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  _saveMemo(_pureDate(selectedDay), value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✨ [삭제] 수정된 파일 목록을 보여주는 위젯 전체 삭제
  // Widget _buildCreatedFilesList(DateTime selectedDay) { ... }
}
