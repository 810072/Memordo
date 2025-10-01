// lib/layout/bottom_section_controller.dart
import 'package:flutter/material.dart';

class BottomSectionController extends ChangeNotifier {
  String _summaryText = '';
  bool _isLoading = false;

  // ✨ [수정] 탭 인덱스: 0: 파일, 1: 개요, 2: 스크래치패드
  int _activeRightSidebarTab = 0;

  String get summaryText => _summaryText;
  bool get isLoading => _isLoading;
  int get activeRightSidebarTab => _activeRightSidebarTab;

  void clearSummary() {
    _summaryText = '';
    _isLoading = false;
    notifyListeners();
  }

  void updateSummary(String summary) {
    _summaryText = summary;
    notifyListeners();
  }

  void setIsLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setActiveTab(int index) {
    // ✨ [수정] 탭 인덱스는 0, 1, 2만 가능
    if (_activeRightSidebarTab != index && index >= 0 && index <= 2) {
      _activeRightSidebarTab = index;
      notifyListeners();
    }
  }
}
