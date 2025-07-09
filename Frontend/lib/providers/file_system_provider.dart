// Frontend/lib/providers/file_system_provider.dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../model/file_system_entry.dart';
import 'package:file_picker/file_picker.dart';

class FileSystemProvider extends ChangeNotifier {
  List<FileSystemEntry> _fileSystemEntries = [];
  bool _isLoading = false;
  String? _lastSavedDirectoryPath; // 마지막으로 저장된 폴더 경로

  // MeetingScreen으로 전달할 선택된 파일 (SideBar에서 파일 탭 시)
  FileSystemEntry? _selectedFileForMeetingScreen;

  List<FileSystemEntry> get fileSystemEntries => _fileSystemEntries;
  bool get isLoading => _isLoading;
  String? get lastSavedDirectoryPath => _lastSavedDirectoryPath;
  FileSystemEntry? get selectedFileForMeetingScreen =>
      _selectedFileForMeetingScreen;

  // MeetingScreen이 로드할 파일을 설정하는 메서드
  void setSelectedFileForMeetingScreen(FileSystemEntry? entry) {
    _selectedFileForMeetingScreen = entry;
    notifyListeners(); // 변경 사항을 구독자에게 알림
  }

  // 파일 시스템 스캔 및 업데이트
  Future<void> scanForFileSystem() async {
    if (kIsWeb) {
      _isLoading = false;
      _fileSystemEntries = [];
      notifyListeners();
      return;
    }
    _isLoading = true;
    _fileSystemEntries = [];
    notifyListeners();

    try {
      final notesDirPath = await getOrCreateNoteFolderPath();
      final rootDirectory = Directory(notesDirPath);
      if (await rootDirectory.exists()) {
        final List<FileSystemEntry> entries = [];
        await _buildDirectoryTree(rootDirectory, entries);
        _sortEntries(entries);
        _fileSystemEntries = entries;
      }
    } catch (e) {
      debugPrint('파일 시스템 스캔 오류: $e');
      // 오류 처리 로직 추가 (예: 사용자에게 스낵바 메시지 표시)
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 재귀적으로 디렉토리를 탐색하고 FileSystemEntry를 빌드하는 헬퍼 함수
  Future<void> _buildDirectoryTree(
    Directory directory,
    List<FileSystemEntry> parentChildren,
  ) async {
    final List<FileSystemEntity> entities = directory.listSync();
    List<FileSystemEntry> currentDirChildren = [];

    for (var entity in entities) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        final List<FileSystemEntry> dirChildren = [];
        await _buildDirectoryTree(entity, dirChildren);
        currentDirChildren.add(
          FileSystemEntry(
            name: name,
            path: entity.path,
            isDirectory: true,
            children: dirChildren,
          ),
        );
      } else if (entity is File &&
          p.extension(entity.path).toLowerCase() == '.md') {
        currentDirChildren.add(
          FileSystemEntry(name: name, path: entity.path, isDirectory: false),
        );
      }
    }
    _sortEntries(currentDirChildren);
    parentChildren.addAll(currentDirChildren);
  }

  // 파일 시스템 항목 정렬 헬퍼 함수
  void _sortEntries(List<FileSystemEntry> entries) {
    entries.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  // 기본 노트 폴더 경로 가져오기 및 생성
  Future<String> getOrCreateNoteFolderPath() async {
    if (kIsWeb) {
      throw UnsupportedError('웹 환경에서는 로컬 파일 시스템에 접근할 수 없습니다.');
    }
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('사용자 홈 디렉터리를 찾을 수 없습니다.');
    final folderPath =
        Platform.isMacOS
            ? p.join(home, 'Memordo_Notes')
            : p.join(home, 'Documents', 'Memordo_Notes');
    final directory = Directory(folderPath);
    if (!await directory.exists()) await directory.create(recursive: true);
    return folderPath;
  }

  // 새 폴더 생성
  Future<bool> createNewFolder(BuildContext context, String folderName) async {
    if (kIsWeb) return false;
    try {
      String parentPath =
          _lastSavedDirectoryPath ?? await getOrCreateNoteFolderPath();
      final newFolderPath = p.join(parentPath, folderName);
      final newDirectory = Directory(newFolderPath);

      if (await newDirectory.exists()) {
        _showSnackBar(context, '이미 같은 이름의 폴더가 존재합니다. ❌', isError: true);
        return false;
      }

      await newDirectory.create(recursive: false);
      _showSnackBar(context, '폴더 생성 완료: $folderName ✅');
      await scanForFileSystem();
      return true;
    } catch (e) {
      _showSnackBar(context, '폴더 생성 중 오류 발생: $e ❌', isError: true);
      return false;
    }
  }

  // 파일/폴더 이름 변경
  Future<bool> renameEntry(
    BuildContext context,
    FileSystemEntry entry,
    String newName,
  ) async {
    if (kIsWeb) return false;
    try {
      String newPath = p.join(p.dirname(entry.path), newName);
      if (await FileSystemEntity.type(newPath) !=
          FileSystemEntityType.notFound) {
        _showSnackBar(context, '이미 같은 이름의 파일/폴더가 존재합니다. ❌', isError: true);
        return false;
      }

      if (entry.isDirectory) {
        await Directory(entry.path).rename(newPath);
      } else {
        await File(entry.path).rename(newPath);
      }
      _showSnackBar(context, '이름 변경 완료: ${entry.name} -> $newName ✅');
      await scanForFileSystem();
      return true;
    } catch (e) {
      _showSnackBar(context, '이름 변경 중 오류 발생: $e ❌', isError: true);
      return false;
    }
  }

  // 파일/폴더 삭제
  Future<bool> deleteEntry(BuildContext context, FileSystemEntry entry) async {
    if (kIsWeb) return false;
    bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('삭제 확인'),
            content: Text('${entry.name}을(를) 정말 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
    if (confirm != true) return false;

    try {
      if (entry.isDirectory) {
        await Directory(entry.path).delete(recursive: true);
      } else {
        await File(entry.path).delete();
      }
      _showSnackBar(context, '삭제 완료: ${entry.name} ✅');
      await scanForFileSystem();
      return true;
    } catch (e) {
      _showSnackBar(context, '삭제 중 오류 발생: $e ❌', isError: true);
      return false;
    }
  }

  // 내부에서 사용할 SnackBar 헬퍼 (BuildContext가 필요하므로 Provider 외부에서 호출)
  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        margin: const EdgeInsets.all(16.0),
      ),
    );
  }

  void updateLastSavedDirectoryPath(String? path) {
    _lastSavedDirectoryPath = path;
    // notifyListeners(); // 이 상태 변경은 UI 갱신을 트리거할 필요는 없음
  }
}
