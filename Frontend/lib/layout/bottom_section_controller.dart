import 'package:flutter/material.dart';

class BottomSectionController extends ChangeNotifier {
  String _summaryText = '';
  bool _isLoading = false;
  bool _isVisible = true; // 하단 영역 보이기/숨기기 상태

  String get summaryText => _summaryText;
  bool get isLoading => _isLoading;
  bool get isVisible => _isVisible;

  void updateSummary(String summary) {
    _summaryText = summary;
    notifyListeners(); // 상태 변경 알림
  }

  void setIsLoading(bool loading) {
    _isLoading = loading;
    notifyListeners(); // 상태 변경 알림
  }

  void toggleVisibility() {
    _isVisible = !_isVisible;
    notifyListeners(); // 상태 변경 알림
  }

  // 필요에 따라 높이 조절 기능도 여기에 추가할 수 있습니다.
  // 예를 들어, 하단 영역의 최대/최소 높이를 설정하는 메서드
  // void setHeight(double height) {
  //   // ...
  //   notifyListeners();
  // }
}
