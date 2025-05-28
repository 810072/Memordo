// lib/layout/ai_summary_controller.dart
import 'package:flutter/material.dart';

class AiSummaryController extends ChangeNotifier {
  String _summaryText = '';
  bool _isLoading = false;
  // bool _isVisible = true; // 제거

  String get summaryText => _summaryText;
  bool get isLoading => _isLoading;

  void updateSummary(String summary) {
    _summaryText = summary;
    notifyListeners();
  }

  void setIsLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void clearSummary() {
    _summaryText = '';
    _isLoading = false;
    notifyListeners();
  }
}
