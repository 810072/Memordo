// lib/features/calendar_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../viewmodels/calendar_viewmodel.dart'; // ✨ [추가] CalendarViewModel 임포트

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  // ✨ [수정] 로컬 상태를 ViewModel로 이전
  // DateTime _focusedDay = DateTime.now();
  // DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  final Map<DateTime, String> _memoData = {};
  final TextEditingController _memoController = TextEditingController();

  final Map<DateTime, List<String>> _createdFilesData = {};

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
    _loadCreatedFilesData();
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

  Future<void> _loadCreatedFilesData() async {
    try {
      final notesDir = await _getNotesDirectory();
      final directory = Directory(notesDir);
      final files = await _getAllMarkdownFiles(directory);

      final Map<DateTime, List<String>> fileData = {};
      for (final file in files) {
        final stat = await file.stat();
        final modifiedDate = _pureDate(stat.modified);
        final fileName = p.basename(file.path);

        if (fileData.containsKey(modifiedDate)) {
          fileData[modifiedDate]!.add(fileName);
        } else {
          fileData[modifiedDate] = [fileName];
        }
      }

      if (mounted) {
        setState(() {
          _createdFilesData.clear();
          _createdFilesData.addAll(fileData);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('노트 파일을 불러오는 중 오류 발생: $e')));
      }
    }
  }

  Future<String> _getNotesDirectory() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('홈 디렉토리를 찾을 수 없습니다.');
    return Platform.isMacOS
        ? p.join(home, 'Memordo_Notes')
        : p.join(home, 'Documents', 'Memordo_Notes');
  }

  Future<List<File>> _getAllMarkdownFiles(Directory dir) async {
    final List<File> mdFiles = [];
    if (!await dir.exists()) return mdFiles;

    await for (var entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.md') {
        mdFiles.add(entity);
      }
    }
    return mdFiles;
  }

  @override
  Widget build(BuildContext context) {
    // ✨ [수정] ViewModel을 watch하여 UI를 최신 상태로 유지
    final calendarViewModel = context.watch<CalendarViewModel>();

    // ✨ [수정] _buildTopBar() 호출 및 Column 제거
    return _buildCalendarWithMemo(calendarViewModel);
  }

  // ✨ [수정] _buildTopBar() 메서드 전체 삭제

  // ✨ [수정] ViewModel을 인자로 받도록 변경
  Widget _buildCalendarWithMemo(CalendarViewModel viewModel) {
    return Expanded(
      child: SingleChildScrollView(
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
              // ✨ [수정] ViewModel을 인자로 전달
              child: _buildCalendarView(viewModel),
            ),
            const SizedBox(height: 24),
            // ✨ [수정] ViewModel의 상태를 사용
            if (viewModel.selectedDay != null) ...[
              _buildCreatedFilesList(viewModel.selectedDay!),
              const SizedBox(height: 16),
              _buildMemoSection(viewModel.selectedDay!),
            ],
          ],
        ),
      ),
    );
  }

  // ✨ [수정] ViewModel을 인자로 받도록 변경
  Widget _buildCalendarView(CalendarViewModel viewModel) {
    return TableCalendar(
      firstDay: DateTime.utc(2010, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      // ✨ [수정] ViewModel의 상태를 사용
      focusedDay: viewModel.focusedDay,
      calendarFormat: _calendarFormat,
      selectedDayPredicate: (day) => isSameDay(viewModel.selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        // ✨ [수정] ViewModel의 메서드 호출
        viewModel.onDaySelected(selectedDay, focusedDay);
        _memoController.text = _memoData[_pureDate(selectedDay)] ?? '';
      },
      onPageChanged: (focusedDay) {
        // ✨ [추가] 페이지 변경 시 ViewModel 업데이트
        viewModel.setFocusedDay(focusedDay);
      },
      eventLoader: (day) {
        final pure = _pureDate(day);
        final List<String> events = [];
        if (_memoData.containsKey(pure) && _memoData[pure]!.isNotEmpty) {
          events.add('memo');
        }
        if (_createdFilesData.containsKey(pure)) {
          events.add('file');
        }
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
                        color:
                            event == 'memo' ? Colors.green : Colors.blueAccent,
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

  // ✨ [수정] 선택된 날짜를 인자로 받도록 변경
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

  // ✨ [수정] 선택된 날짜를 인자로 받도록 변경
  Widget _buildCreatedFilesList(DateTime selectedDay) {
    final pureSelectedDay = _pureDate(selectedDay);
    final files = _createdFilesData[pureSelectedDay];

    if (files == null || files.isEmpty) {
      return const SizedBox.shrink();
    }

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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "해당 날짜에 수정한 노트",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Column(
                children:
                    files
                        .map(
                          (fileName) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.description_outlined,
                              color: Colors.blueAccent,
                              size: 20,
                            ),
                            title: Text(
                              fileName,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
