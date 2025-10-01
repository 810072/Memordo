// lib/providers/status_bar_provider.dart
import 'package:flutter/material.dart';
import 'dart:async';

enum StatusType { success, error, info }

class NotificationLog {
  final String message;
  final StatusType type;
  final DateTime timestamp;

  NotificationLog({
    required this.message,
    required this.type,
    required this.timestamp,
  });
}

class StatusBarProvider with ChangeNotifier {
  String _message = '';
  StatusType _type = StatusType.info;
  bool _isVisible = false;
  Timer? _timer;

  // ✨ [수정] 로그 최대 개수를 100개로 제한
  static const int _maxLogs = 100;
  final List<NotificationLog> _logs = [];
  bool _hasUnread = false;

  int _line = 0;
  int _char = 0;
  int _totalChars = 0;

  String get message => _message;
  StatusType get type => _type;
  bool get isVisible => _isVisible;
  List<NotificationLog> get logs => _logs;
  bool get hasUnread => _hasUnread;

  int get line => _line;
  int get char => _char;
  int get totalChars => _totalChars;

  void updateTextInfo({int line = 0, int char = 0, int totalChars = 0}) {
    _line = line;
    _char = char;
    _totalChars = totalChars;
    notifyListeners();
  }

  void clearTextInfo() {
    _line = 0;
    _char = 0;
    _totalChars = 0;
    notifyListeners();
  }

  void showStatusMessage(
    String message, {
    StatusType type = StatusType.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    _message = message;
    _type = type;
    _isVisible = true;

    final newLog = NotificationLog(
      message: message,
      type: type,
      timestamp: DateTime.now(),
    );
    _logs.insert(0, newLog);
    // ✨ [추가] 로그가 최대 개수를 초과하면 가장 오래된 로그를 제거합니다.
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
    _hasUnread = true;

    notifyListeners();

    _timer?.cancel();
    _timer = Timer(duration, () {
      _isVisible = false;
      notifyListeners();
    });
  }

  void markAsRead() {
    if (_hasUnread) {
      _hasUnread = false;
      notifyListeners();
    }
  }
}
