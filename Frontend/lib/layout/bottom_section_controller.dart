// lib/layout/bottom_section_controller.dart
import 'package:flutter/material.dart';

class BottomSectionController extends ChangeNotifier {
  String _summaryText = '';
  bool _isLoading = false;

  // 오른쪽 사이드바의 활성 탭 인덱스를 관리합니다 (0: 파일, 1: AI 요약).
  int _activeRightSidebarTab = 0;

  String get summaryText => _summaryText;
  bool get isLoading => _isLoading;
  int get activeRightSidebarTab => _activeRightSidebarTab;

  // 요약 내용을 초기화합니다.
  void clearSummary() {
    _summaryText = '';
    _isLoading = false; // 로딩 상태도 함께 초기화
    notifyListeners();
  }

  // 요약 내용을 업데이트합니다.
  void updateSummary(String summary) {
    _summaryText = summary;
    notifyListeners();
  }

  // 로딩 상태를 설정합니다.
  void setIsLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // 오른쪽 사이드바의 탭을 프로그래밍 방식으로 변경합니다.
  void setActiveTab(int index) {
    if (_activeRightSidebarTab != index) {
      _activeRightSidebarTab = index;
      notifyListeners();
    }
  }
}
