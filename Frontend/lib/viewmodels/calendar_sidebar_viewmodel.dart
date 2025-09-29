import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../model/file_system_entry.dart';

class CalendarSidebarViewModel with ChangeNotifier {
  bool _isLoading = false;
  List<FileSystemEntry> _modifiedNotes = [];

  bool get isLoading => _isLoading;
  List<FileSystemEntry> get modifiedNotes => _modifiedNotes;

  Future<void> fetchModifiedNotes(DateTime? selectedDate) async {
    if (selectedDate == null) {
      _modifiedNotes = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final pureSelectedDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
      final notesDir = await _getNotesDirectory();
      final directory = Directory(notesDir);
      final files = await _getAllMarkdownFiles(directory);

      final List<FileSystemEntry> dailyNotes = [];
      for (final file in files) {
        final stat = await file.stat();
        final modifiedDate = stat.modified;
        final pureModifiedDate = DateTime(
          modifiedDate.year,
          modifiedDate.month,
          modifiedDate.day,
        );

        if (pureModifiedDate.isAtSameMomentAs(pureSelectedDate)) {
          dailyNotes.add(
            FileSystemEntry(
              name: p.basename(file.path),
              path: file.path,
              isDirectory: false,
              modifiedTime: modifiedDate, // ✨ [추가] 수정 시간 정보 전달
            ),
          );
        }
      }
      _modifiedNotes = dailyNotes;
    } catch (e) {
      debugPrint('수정된 노트 로딩 오류: $e');
      _modifiedNotes = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> _getNotesDirectory() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('사용자 홈 디렉토리를 찾을 수 없습니다.');
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
}
