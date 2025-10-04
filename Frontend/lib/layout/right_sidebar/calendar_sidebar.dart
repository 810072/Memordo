// lib/layout/right_sidebar/calendar_sidebar.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import '../../viewmodels/calendar_viewmodel.dart';
import '../../viewmodels/calendar_sidebar_viewmodel.dart';
import '../../providers/file_system_provider.dart';
import '../../model/file_system_entry.dart';

class CalendarSidebar extends StatefulWidget {
  const CalendarSidebar({Key? key}) : super(key: key);

  @override
  State<CalendarSidebar> createState() => _CalendarSidebarState();
}

class _CalendarSidebarState extends State<CalendarSidebar> {
  late CalendarViewModel _calendarViewModel;
  late CalendarSidebarViewModel _sidebarViewModel;
  DateTime? _lastFetchedDay;

  @override
  void initState() {
    super.initState();
    _calendarViewModel = Provider.of<CalendarViewModel>(context, listen: false);
    _sidebarViewModel = Provider.of<CalendarSidebarViewModel>(
      context,
      listen: false,
    );
    _calendarViewModel.addListener(_onSelectedDayChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchNotesForSelectedDayIfNeeded();
    });
  }

  @override
  void dispose() {
    _calendarViewModel.removeListener(_onSelectedDayChange);
    super.dispose();
  }

  void _onSelectedDayChange() {
    _fetchNotesForSelectedDayIfNeeded();
  }

  void _fetchNotesForSelectedDayIfNeeded() {
    final currentSelectedDay = _calendarViewModel.selectedDay;
    if (_lastFetchedDay != currentSelectedDay) {
      _lastFetchedDay = currentSelectedDay;
      _sidebarViewModel.fetchModifiedNotes(currentSelectedDay);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calendarViewModel = context.watch<CalendarViewModel>();
    final sidebarViewModel = context.watch<CalendarSidebarViewModel>();

    return Column(
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              DateFormat(
                'yyyy년 MM월 dd일 (E)',
                'ko_KR',
              ).format(calendarViewModel.selectedDay),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ),
        Expanded(
          child:
              sidebarViewModel.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : sidebarViewModel.modifiedNotes.isEmpty
                  ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        '이 날짜에 수정된 노트가 없습니다.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                  : _buildNotesList(sidebarViewModel),
        ),
      ],
    );
  }

  Widget _buildNotesList(CalendarSidebarViewModel sidebarViewModel) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
      itemCount: sidebarViewModel.modifiedNotes.length,
      itemBuilder: (context, index) {
        final note = sidebarViewModel.modifiedNotes[index];
        final formattedTime =
            note.modifiedTime != null
                ? DateFormat('HH:mm:ss').format(note.modifiedTime!)
                : '';

        return ListTile(
          leading: const Icon(Icons.description_outlined, size: 20),
          title: Text(
            p.basenameWithoutExtension(note.name),
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '수정된 시간: $formattedTime',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          dense: true,
          onTap: () {
            Provider.of<FileSystemProvider>(
              context,
              listen: false,
            ).setSelectedFileForMeetingScreen(note);
          },
        );
      },
    );
  }
}
