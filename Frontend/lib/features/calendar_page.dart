// Frontend/lib/features/calendar_page.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io'; // ✨ [추가] dart:io 임포트
import 'package:path/path.dart' as p; // ✨ [추가] path 패키지 임포트

// import 'page_type.dart'; // PageType 임포트는 유지

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // 기존 메모 데이터
  final Map<DateTime, String> _memoData = {};
  final TextEditingController _memoController = TextEditingController();

  // ✨ [추가] 파일 수정일 데이터를 저장할 상태 변수
  final Map<DateTime, List<String>> _createdFilesData = {};

  @override
  void initState() {
    super.initState();
    // 기존 메모와 파일 데이터를 함께 로드
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

  // --- 기존 메모 저장/로드 함수 (변경 없음) ---
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

  // --- ✨ [추가] 파일 시스템 관련 함수들 (GraphPage 참고) ---

  Future<void> _loadCreatedFilesData() async {
    try {
      final notesDir = await _getNotesDirectory();
      final directory = Directory(notesDir);
      final files = await _getAllMarkdownFiles(directory);

      final Map<DateTime, List<String>> fileData = {};
      for (final file in files) {
        final stat = await file.stat();
        // '수정일'을 기준으로 날짜 정규화
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
      // 에러 처리 (예: 스낵바 표시)
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

  // --- UI 빌드 함수들 (일부 수정됨) ---

  @override
  Widget build(BuildContext context) {
    return Column(children: [_buildTopBar(), _buildCalendarWithMemo()]);
  }

  Widget _buildTopBar() {
    // (기존 코드와 동일)
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor,
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
                  const SizedBox(height: 24),
                  // ✨ [수정] 선택된 날짜에 파일 목록 또는 메모 섹션 표시
                  if (_selectedDay != null) ...[
                    _buildCreatedFilesList(),
                    const SizedBox(height: 16),
                    _buildMemoSection(),
                  ],
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
      // ✨ [수정] eventLoader: 메모와 파일 수정일을 모두 이벤트로 감지
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
      // ✨ [수정] calendarBuilders: 이벤트 유형에 따라 다른 색상의 마커 표시
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          if (events.isEmpty) return const SizedBox.shrink();

          return Positioned(
            right: 5,
            bottom: 5,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children:
                  events.map((event) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        // 'memo'는 초록색, 'file'은 파란색
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

  Widget _buildMemoSection() {
    // (기존 코드와 거의 동일, 제목 추가)
    return Column(
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
              _saveMemo(_pureDate(_selectedDay!), value);
            },
          ),
        ),
      ],
    );
  }

  // ✨ [추가] 선택된 날짜에 수정된 파일 목록을 보여주는 위젯
  Widget _buildCreatedFilesList() {
    final pureSelectedDay = _pureDate(_selectedDay!);
    final files = _createdFilesData[pureSelectedDay];

    if (files == null || files.isEmpty) {
      return const SizedBox.shrink(); // 파일이 없으면 아무것도 표시하지 않음
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "해당 날짜에 수정한 노트",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children:
                files
                    .map(
                      (fileName) => ListTile(
                        leading: const Icon(
                          Icons.description_outlined,
                          color: Colors.blueAccent,
                        ),
                        title: Text(
                          fileName,
                          style: const TextStyle(fontSize: 14),
                        ),
                        dense: true,
                      ),
                    )
                    .toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
