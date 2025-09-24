// lib/providers/tab_provider.dart
import 'dart:async'; // Timer를 사용하기 위해 추가
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../model/note_model.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../widgets/obsidian_markdown_controller.dart';

class TabProvider with ChangeNotifier {
  final List<NoteTab> _openTabs = [];
  int _activeTabIndex = -1;
  Timer? _debounce; // ✨ 자동 저장을 위한 타이머 변수 추가
  VoidCallback? onTabOpenedFromExternalWindow;

  List<NoteTab> get openTabs => _openTabs;
  int get activeTabIndex => _activeTabIndex;
  NoteTab? get activeTab =>
      _activeTabIndex != -1 ? _openTabs[_activeTabIndex] : null;

  // ✨ 자동 저장 로직
  Future<void> _autoSave(NoteTab tab) async {
    // 파일 경로가 없는 새 메모는 자동 저장하지 않음
    if (tab.filePath == null || tab.filePath!.isEmpty) return;

    try {
      final content = tab.controller.text;
      await File(tab.filePath!).writeAsString(content);
      print('📝 자동 저장 완료: ${tab.title}');
    } catch (e) {
      print('❌ 자동 저장 실패: ${e.toString()}');
    }
  }

  // ✨ 탭 내용이 변경될 때 호출되는 리스너
  void _onContentChanged(NoteTab tab) {
    // 기존 타이머가 있으면 취소
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    // 3초 후에 자동 저장 실행
    _debounce = Timer(const Duration(seconds: 3), () {
      _autoSave(tab);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel(); // Provider가 소멸될 때 타이머 취소
    super.dispose();
  }

  // ✨ [추가] 탭 순서 변경 메서드
  void reorderTab(int oldIndex, int newIndex) {
    // newIndex가 oldIndex 이후의 위치로 이동하는 경우,
    // 리스트에서 oldIndex의 아이템이 삭제되면 newIndex가 하나 줄어들기 때문에 조정이 필요합니다.
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final NoteTab item = _openTabs.removeAt(oldIndex);
    _openTabs.insert(newIndex, item);

    // 활성 탭의 인덱스를 업데이트합니다.
    if (_activeTabIndex == oldIndex) {
      _activeTabIndex = newIndex;
    } else if (_activeTabIndex >= newIndex && _activeTabIndex < oldIndex) {
      _activeTabIndex += 1;
    } else if (_activeTabIndex <= newIndex && _activeTabIndex > oldIndex) {
      _activeTabIndex -= 1;
    }

    notifyListeners();
  }

  void openNewTab({String? filePath, String? content}) {
    if (filePath != null) {
      final existingTabIndex = _openTabs.indexWhere(
        (tab) => tab.filePath == filePath,
      );
      if (existingTabIndex != -1) {
        setActiveTab(existingTabIndex);
        onTabOpenedFromExternalWindow?.call(); // ✨ 콜백 호출
        return;
      }
    }

    final String id = filePath ?? const Uuid().v4();
    final String title =
        filePath != null ? p.basenameWithoutExtension(filePath) : '새 메모';

    final newTab = NoteTab(
      id: id,
      title: title,
      controller: ObsidianMarkdownController(text: content ?? '', styleMap: {}),
      focusNode: FocusNode(),
      filePath: filePath,
    );

    // ✨ 새로 생성된 탭의 컨트롤러에 리스너 추가
    newTab.controller.addListener(() => _onContentChanged(newTab));

    _openTabs.add(newTab);
    _activeTabIndex = _openTabs.length - 1;
    onTabOpenedFromExternalWindow?.call(); // ✨ 콜백 호출
    notifyListeners();
  }

  void setActiveTab(int index) {
    if (index >= 0 && index < _openTabs.length) {
      _activeTabIndex = index;
      onTabOpenedFromExternalWindow?.call(); // ✨ 콜백 호출
      notifyListeners();
    }
  }

  void closeTab(int index) {
    if (index >= 0 && index < _openTabs.length) {
      // ✨ 탭을 닫을 때 리스너도 제거
      _openTabs[index].controller.removeListener(
        () => _onContentChanged(_openTabs[index]),
      );
      _openTabs[index].controller.dispose();
      _openTabs[index].focusNode.dispose();
      _openTabs.removeAt(index);

      if (_openTabs.isEmpty) {
        _activeTabIndex = -1;
      } else if (_activeTabIndex >= index) {
        _activeTabIndex = (_activeTabIndex - 1).clamp(0, _openTabs.length - 1);
      }
      notifyListeners();
    }
  }

  void updateTabInfo(int index, String newFilePath) {
    if (index >= 0 && index < _openTabs.length) {
      final tab = _openTabs[index];
      tab.filePath = newFilePath;
      tab.id = newFilePath;
      tab.title = p.basenameWithoutExtension(newFilePath);
      notifyListeners();
    }
  }
}
