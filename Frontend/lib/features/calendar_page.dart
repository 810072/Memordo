// Frontend/lib/features/calendar_page.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'page_type.dart'; // PageType 임포트는 유지

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  final Map<DateTime, String> _memoData = {};
  final TextEditingController _memoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
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

  @override
  Widget build(BuildContext context) {
    return Column(children: [_buildTopBar(), _buildCalendarWithMemo()]);
  }

  Widget _buildTopBar() {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor,
        // ✨ [수정] 구분선 색상을 테마에서 가져옵니다.
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Calendar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _focusedDay = DateTime.now();
                _selectedDay = null;
              });
            },
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

  Widget _buildCalendarWithMemo() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          elevation: 3.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCalendarView(),
                  const SizedBox(height: 16),
                  if (_selectedDay != null) _buildMemoSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    return TableCalendar(
      firstDay: DateTime.utc(2010, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      calendarFormat: _calendarFormat,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
          _memoController.text = _memoData[_pureDate(selectedDay)] ?? '';
        });
      },
      eventLoader: (day) {
        final pure = _pureDate(day);
        if (_memoData.containsKey(pure) && _memoData[pure]!.isNotEmpty) {
          return ['memo'];
        }
        return [];
      },
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          if (events.isNotEmpty) {
            return Positioned(
              bottom: 10,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }
          return const SizedBox();
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

  Widget _buildMemoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _memoController,
        maxLines: 10,
        style: const TextStyle(fontSize: 14),
        decoration: const InputDecoration(
          hintText: "메모를 작성하세요.",
          hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
          border: InputBorder.none,
        ),
        onChanged: (value) {
          _saveMemo(_pureDate(_selectedDay!), value);
        },
      ),
    );
  }
}
