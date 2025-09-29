import 'package:flutter/material.dart';
import 'dart:async';

// 상태 종류 (성공, 오류, 정보)
enum StatusType { success, error, info }

// 알림 로그 데이터 모델
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

  // 알림 로그 기록 및 읽음 상태 관리
  final List<NotificationLog> _logs = [];
  bool _hasUnread = false;

  String get message => _message;
  StatusType get type => _type;
  bool get isVisible => _isVisible;
  List<NotificationLog> get logs => _logs;
  bool get hasUnread => _hasUnread;

  void showStatusMessage(
    String message, {
    StatusType type = StatusType.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    _message = message;
    _type = type;
    _isVisible = true;

    // 새 알림을 로그에 추가하고, '읽지 않음' 상태로 설정
    final newLog = NotificationLog(
      message: message,
      type: type,
      timestamp: DateTime.now(),
    );
    _logs.insert(0, newLog); // 최신 알림이 맨 위에 오도록
    _hasUnread = true;

    notifyListeners();

    _timer?.cancel();
    _timer = Timer(duration, () {
      _isVisible = false;
      notifyListeners();
    });
  }

  // 알림 로그를 확인했을 때 호출할 함수
  void markAsRead() {
    if (_hasUnread) {
      _hasUnread = false;
      notifyListeners();
    }
  }
}
