// lib/providers/chat_session_provider.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/chat_session.dart';
import '../model/chat_message_model.dart';

class ChatSessionProvider with ChangeNotifier {
  static const _prefsKey = 'chat_sessions';
  static const _activeSessionIdKey = 'active_chat_session_id';

  List<ChatSession> _sessions = [];
  String? _activeSessionId;

  List<ChatSession> get sessions => _sessions;
  ChatSession? get activeSession {
    if (_activeSessionId == null) return null;
    try {
      return _sessions.firstWhere((s) => s.id == _activeSessionId);
    } catch (e) {
      // 활성 ID가 있지만 세션 목록에 없는 경우
      if (_sessions.isNotEmpty) {
        _activeSessionId = _sessions.first.id;
        return _sessions.first;
      }
      return null;
    }
  }

  ChatSessionProvider() {
    loadSessions();
  }

  Future<void> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();

    // ✨ [수정] getString 대신 getStringList를 사용하여 세션 목록을 불러옵니다.
    final List<String>? jsonList = prefs.getStringList(_prefsKey);
    if (jsonList != null) {
      try {
        // ✨ [수정] String 리스트를 순회하며 각 항목을 개별적으로 JSON 디코딩합니다.
        _sessions =
            jsonList
                .map(
                  (jsonString) => ChatSession.fromJson(
                    jsonDecode(jsonString) as Map<String, dynamic>,
                  ),
                )
                .toList();
      } catch (e) {
        debugPrint('ChatSession 로드 실패: $e');
        _sessions = [];
      }
    }

    // 세션이 없으면 새로 생성
    if (_sessions.isEmpty) {
      _sessions.add(ChatSession.createNew());
    }

    // 활성 세션 ID 로드
    _activeSessionId = prefs.getString(_activeSessionIdKey);

    // 활성 세션 ID가 유효하지 않으면 첫 번째 세션으로 설정
    if (_activeSessionId == null ||
        !_sessions.any((s) => s.id == _activeSessionId)) {
      _activeSessionId = _sessions.first.id;
    }

    notifyListeners();
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();

    // 세션 목록을 JSON 문자열 리스트로 변환 (SharedPreferences 제한 때문)
    final List<String> encodedList =
        _sessions.map((s) => jsonEncode(s.toJson())).toList();
    // SharedPreferences는 List<String> 저장을 지원합니다.
    await prefs.setStringList(_prefsKey, encodedList);

    // 활성 세션 ID 저장
    if (_activeSessionId != null) {
      await prefs.setString(_activeSessionIdKey, _activeSessionId!);
    }
  }

  void createNewSession() {
    final newSession = ChatSession.createNew();
    _sessions.add(newSession);
    _activeSessionId = newSession.id;

    _saveSessions();
    notifyListeners();
  }

  void setActiveSession(String id) {
    if (_activeSessionId != id) {
      _activeSessionId = id;
      _saveSessions(); // 활성 세션 ID만 저장
      notifyListeners();
    }
  }

  void deleteSession(String id) {
    if (_sessions.length <= 1) return; // 마지막 세션은 삭제 방지

    _sessions.removeWhere((s) => s.id == id);

    if (_activeSessionId == id) {
      _activeSessionId = _sessions.first.id;
    }

    _saveSessions();
    notifyListeners();
  }

  void addMessageToActiveSession(ChatMessage message) {
    final session = activeSession;
    if (session == null) return;

    session.messages.add(message);

    // 첫 사용자 메시지로 제목 자동 업데이트
    if (session.messages.length == 2 && message.isUser) {
      final title =
          message.text.length > 20
              ? '${message.text.substring(2, 22)}...' // '> ' 제거 후 자르기
              : message.text.substring(2); // '> ' 제거
      session.title = title;
    }

    _saveSessions();
    notifyListeners();
  }
}
