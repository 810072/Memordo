// lib/layout/bottom_section_controller.dart
import 'package:flutter/material.dart';

class BottomSectionController extends ChangeNotifier {
  String _summaryText = '';
  bool _isLoading = false;
  int _activeRightSidebarTab = 0;
  bool _isBottomPanelVisible = false;
  int _activeBottomPanelTab = 0; // 0: AI 요약, 1: AI 챗봇

  // --- ✨ [추가] RAG 모드 상태 ---
  bool _isRagMode = false;

  String get summaryText => _summaryText;
  bool get isLoading => _isLoading;
  int get activeRightSidebarTab => _activeRightSidebarTab;
  bool get isBottomPanelVisible => _isBottomPanelVisible;
  int get activeBottomPanelTab => _activeBottomPanelTab;

  // --- ✨ [추가] RAG 모드 Getter & Setter ---
  bool get isRagMode => _isRagMode; // ✨ 누락된 Getter 추가

  void setRagMode(bool value) {
    // ✨ 누락된 Setter 추가
    if (_isRagMode != value) {
      _isRagMode = value;
      notifyListeners();
    }
  }
  // ---

  void toggleBottomPanel() {
    _isBottomPanelVisible = !_isBottomPanelVisible;
    notifyListeners();
  }

  void showBottomPanel() {
    if (!_isBottomPanelVisible) {
      _isBottomPanelVisible = true;
      notifyListeners();
    }
  }

  void setActiveBottomPanelTab(int index) {
    if (_activeBottomPanelTab != index) {
      _activeBottomPanelTab = index;
      notifyListeners();
    }
  }

  void clearSummary() {
    _summaryText = '';
    _isLoading = false; // 요약 로딩 상태만 초기화
    notifyListeners();
  }

  void updateSummary(String summary) {
    _summaryText = summary;
    notifyListeners();
  }

  void setIsLoading(bool loading) {
    _isLoading = loading;
    if (_isLoading && _activeBottomPanelTab != 0) {
      // 로딩 시작 시 AI 요약 탭 아니면
      _activeBottomPanelTab = 0; // AI 요약 탭으로 이동
      _isBottomPanelVisible = true;
    } else if (_isLoading) {
      // 로딩 시작 시 AI 요약 탭이면
      _isBottomPanelVisible = true; // 패널만 켬
    }
    notifyListeners();
  }

  void setActiveTab(int index) {
    if (_activeRightSidebarTab != index && index >= 0 && index <= 2) {
      _activeRightSidebarTab = index;
      notifyListeners();
    }
  }
}
