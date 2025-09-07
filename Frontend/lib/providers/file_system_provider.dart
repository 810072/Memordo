// Frontend/lib/providers/file_system_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../model/file_system_entry.dart';

class FileSystemProvider extends ChangeNotifier {
  List<FileSystemEntry> _fileSystemEntries = [];
  bool _isLoading = false;
  String? _lastSavedDirectoryPath;
  List<String> _pinnedPaths = [];
  static const String _prefsKeyForPinnedPaths = 'pinned_paths';

  FileSystemEntry? _selectedFileForMeetingScreen;
  String? _selectedFolderPath;

  StreamSubscription<FileSystemEvent>? _directoryWatcher;
  Timer? _debounce;

  final Set<String> _expandedFolderPaths = {};

  List<FileSystemEntry> get fileSystemEntries => _fileSystemEntries;
  bool get isLoading => _isLoading;
  String? get lastSavedDirectoryPath => _lastSavedDirectoryPath;
  FileSystemEntry? get selectedFileForMeetingScreen =>
      _selectedFileForMeetingScreen;
  String? get selectedFolderPath => _selectedFolderPath;
  Set<String> get expandedFolderPaths => _expandedFolderPaths;

  FileSystemProvider() {
    _loadPinnedFiles();
  }

  void setFolderExpanded(String path, bool isExpanded) {
    if (isExpanded) {
      _expandedFolderPaths.add(path);
    } else {
      _expandedFolderPaths.remove(path);
    }
  }

  @override
  void dispose() {
    _directoryWatcher?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void setSelectedFileForMeetingScreen(FileSystemEntry? entry) {
    _selectedFileForMeetingScreen = entry;
    notifyListeners();
  }

  void selectFolder(String? path) {
    if (_selectedFolderPath != path) {
      _selectedFolderPath = path;
      notifyListeners();
    }
  }

  Future<void> _loadPinnedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    _pinnedPaths = prefs.getStringList(_prefsKeyForPinnedPaths) ?? [];
    notifyListeners();
  }

  Future<void> _savePinnedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKeyForPinnedPaths, _pinnedPaths);
  }

  Future<void> togglePinStatus(FileSystemEntry entry) async {
    if (_pinnedPaths.contains(entry.path)) {
      _pinnedPaths.remove(entry.path);
    } else {
      _pinnedPaths.add(entry.path);
    }
    await _savePinnedFiles();
    await scanForFileSystem();
  }

  Future<void> scanForFileSystem() async {
    if (kIsWeb) {
      _isLoading = false;
      _fileSystemEntries = [];
      notifyListeners();
      return;
    }
    if (!_isLoading) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      await _loadPinnedFiles();
      final notesDirPath = await getOrCreateNoteFolderPath();
      _watchDirectory(notesDirPath);
      final rootDirectory = Directory(notesDirPath);
      if (await rootDirectory.exists()) {
        final List<FileSystemEntry> entries = [];
        await _buildDirectoryTree(rootDirectory, entries);
        _markPinnedEntries(entries);
        _sortEntries(entries);
        _fileSystemEntries = entries;
      }
    } catch (e) {
      debugPrint('파일 시스템 스캔 오류: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _watchDirectory(String path) {
    if (kIsWeb || _directoryWatcher != null) return;
    try {
      final directory = Directory(path);
      _directoryWatcher = directory
          .watch(recursive: true)
          .listen(
            (FileSystemEvent event) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), () {
                debugPrint('📁 파일 시스템 변경 감지: ${event.path}');
                scanForFileSystem();
              });
            },
            onError: (error) {
              debugPrint('디렉토리 감시 오류: $error');
              _directoryWatcher?.cancel();
              _directoryWatcher = null;
            },
          );
      debugPrint('👀 디렉토리 실시간 감시 시작: $path');
    } catch (e) {
      debugPrint('디렉토리 감시 설정 실패: $e');
    }
  }

  void _markPinnedEntries(List<FileSystemEntry> entries) {
    for (var entry in entries) {
      entry.isPinned = _pinnedPaths.contains(entry.path);
      if (entry.isDirectory && entry.children != null) {
        _markPinnedEntries(entry.children!);
      }
    }
  }

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

  void _sortEntries(List<FileSystemEntry> entries) {
    entries.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

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

  // ✨ [추가] 파일/폴더 이동 로직
  Future<bool> moveEntry(
    BuildContext context, {
    required FileSystemEntry entryToMove,
    required String newParentPath,
  }) async {
    if (kIsWeb) return false;

    try {
      final newPath = p.join(newParentPath, entryToMove.name);

      // 자기 자신 또는 자기 하위 폴더로 이동하는 것을 방지
      if (entryToMove.path == newParentPath ||
          p.isWithin(entryToMove.path, newParentPath)) {
        _showSnackBar(context, '자신의 하위 폴더로는 이동할 수 없습니다. ❌', isError: true);
        return false;
      }

      // 같은 경로로 이동하는 경우 무시
      if (newPath == entryToMove.path) {
        return true;
      }

      if (await FileSystemEntity.type(newPath) !=
          FileSystemEntityType.notFound) {
        _showSnackBar(context, '같은 이름의 파일/폴더가 이미 존재합니다. ❌', isError: true);
        return false;
      }

      if (entryToMove.isDirectory) {
        await Directory(entryToMove.path).rename(newPath);
      } else {
        await File(entryToMove.path).rename(newPath);
      }

      _showSnackBar(context, '이동 완료: ${entryToMove.name} ✅');
      await scanForFileSystem(); // 이동 후 파일 목록 새로고침
      return true;
    } catch (e) {
      _showSnackBar(context, '이동 중 오류 발생: $e ❌', isError: true);
      return false;
    }
  }

  Future<bool> createNewFile(
    BuildContext context,
    String fileName, {
    String? parentPath,
  }) async {
    if (kIsWeb) return false;
    try {
      String basePath = parentPath ?? await getOrCreateNoteFolderPath();
      final newFilePath = p.join(basePath, '$fileName.md');
      final newFile = File(newFilePath);
      if (await newFile.exists()) {
        _showSnackBar(context, '이미 같은 이름의 파일이 존재합니다. ❌', isError: true);
        return false;
      }
      await newFile.create();
      await newFile.writeAsString('');
      _showSnackBar(context, '파일 생성 완료: $fileName.md ✅');
      return true;
    } catch (e) {
      _showSnackBar(context, '파일 생성 중 오류 발생: $e ❌', isError: true);
      return false;
    }
  }

  Future<bool> createNewFolder(
    BuildContext context,
    String folderName, {
    String? parentPath,
  }) async {
    if (kIsWeb) return false;
    try {
      String basePath = parentPath ?? await getOrCreateNoteFolderPath();
      final newFolderPath = p.join(basePath, folderName);
      final newDirectory = Directory(newFolderPath);
      if (await newDirectory.exists()) {
        _showSnackBar(context, '이미 같은 이름의 폴더가 존재합니다. ❌', isError: true);
        return false;
      }
      await newDirectory.create(recursive: false);
      _showSnackBar(context, '폴더 생성 완료: $folderName ✅');
      return true;
    } catch (e) {
      _showSnackBar(context, '폴더 생성 중 오류 발생: $e ❌', isError: true);
      return false;
    }
  }

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
      return true;
    } catch (e) {
      _showSnackBar(context, '이름 변경 중 오류 발생: $e ❌', isError: true);
      return false;
    }
  }

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
      return true;
    } catch (e) {
      _showSnackBar(context, '삭제 중 오류 발생: $e ❌', isError: true);
      return false;
    }
  }

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
  }
}
