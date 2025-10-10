// lib/providers/tab_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../model/note_model.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../widgets/markdown_controller.dart';

class TabProvider with ChangeNotifier {
  final List<NoteTab> _openTabs = [];
  int _activeTabIndex = -1;
  Timer? _debounce;
  VoidCallback? onTabOpenedFromExternalWindow;

  List<NoteTab> get openTabs => _openTabs;
  int get activeTabIndex => _activeTabIndex;
  NoteTab? get activeTab =>
      _activeTabIndex != -1 ? _openTabs[_activeTabIndex] : null;

  Future<void> _autoSave(NoteTab tab) async {
    if (tab.filePath == null || tab.filePath!.isEmpty) return;

    try {
      final content = tab.controller.text;
      await File(tab.filePath!).writeAsString(content);
      print('📝 자동 저장 완료: ${tab.title}');
    } catch (e) {
      print('❌ 자동 저장 실패: ${e.toString()}');
    }
  }

  void _onContentChanged(NoteTab tab) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      _autoSave(tab);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // ✨ [추가] Provider가 소멸될 때 모든 탭의 리소스를 정리합니다.
    for (var tab in _openTabs) {
      if (tab.contentListener != null) {
        tab.controller.removeListener(tab.contentListener!);
      }
      tab.controller.dispose();
      tab.focusNode.dispose();
    }
    super.dispose();
  }

  void reorderTab(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final NoteTab item = _openTabs.removeAt(oldIndex);
    _openTabs.insert(newIndex, item);

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
        onTabOpenedFromExternalWindow?.call();
        return;
      }
    }

    final String id = filePath ?? const Uuid().v4();
    final String title =
        filePath != null ? p.basenameWithoutExtension(filePath) : '새 메모';

    final newTab = NoteTab(
      id: id,
      title: title,
      controller: MarkdownController(text: content ?? '', styleMap: {}),
      focusNode: FocusNode(),
      filePath: filePath,
    );

    // ✨ [수정] 각 탭에 고유한 리스너를 할당하여 나중에 제거할 수 있도록 합니다.
    newTab.contentListener = () => _onContentChanged(newTab);
    newTab.controller.addListener(newTab.contentListener!);

    _openTabs.add(newTab);
    _activeTabIndex = _openTabs.length - 1;
    onTabOpenedFromExternalWindow?.call();
    notifyListeners();
  }

  void setActiveTab(int index) {
    if (index >= 0 && index < _openTabs.length) {
      _activeTabIndex = index;
      onTabOpenedFromExternalWindow?.call();
      notifyListeners();
    }
  }

  void closeTab(int index) {
    if (index >= 0 && index < _openTabs.length) {
      final tabToClose = _openTabs[index];
      // ✨ [수정] 탭을 닫을 때 저장된 리스너를 정확하게 제거합니다.
      if (tabToClose.contentListener != null) {
        tabToClose.controller.removeListener(tabToClose.contentListener!);
      }
      tabToClose.controller.dispose();
      tabToClose.focusNode.dispose();
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
