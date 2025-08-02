// lib/providers/token_status_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../model/token_status_model.dart';
import '../services/auth_token.dart';

class TokenStatusProvider with ChangeNotifier {
  static const _cacheKey = 'token_status_cache';

  TokenStatus? _status;
  String? _userEmail; // ✨ [추가] 사용자 이메일 상태

  TokenStatus? get status => _status;
  String? get userEmail => _userEmail; // ✨ [추가] 이메일 getter

  bool get isLoaded => _status != null;
  bool get isAuthenticated => _status?.accessTokenValid == true;
  bool get isGoogleLinked => _status?.isGoogleLinked == true;

  /// 서버 + 캐시 통합 상태 확인
  Future<void> loadStatus(BuildContext context) async {
    try {
      final data = await fetchTokenStatus(context);
      if (data != null) {
        _status = TokenStatus.fromJson(data);
        _userEmail = await getStoredUserEmail(); // ✨ [추가] 이메일 불러오기
        await _saveToCache(data);
      } else {
        await tryRefreshToken(context);
      }
    } catch (e) {
      debugPrint('❌ Token status check failed: $e');
      await clear();
    } finally {
      notifyListeners(); // ✨ [수정] 어떤 경우에도 상태 변경을 알리도록 finally로 이동
    }
  }

  /// 캐시 불러오기
  Future<void> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_cacheKey);
    if (jsonStr != null) {
      try {
        final jsonData = jsonDecode(jsonStr);
        final cached = TokenStatus.fromJson(jsonData);
        if (cached.accessTokenValid || cached.googleAccessTokenValid) {
          _status = cached;
          _userEmail = await getStoredUserEmail(); // ✨ [추가] 이메일 불러오기
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Cache decode error: $e');
      }
    }
  }

  /// 토큰 자동 갱신
  Future<void> tryRefreshToken(BuildContext context) async {
    try {
      debugPrint('🔄 accessToken 만료 → refreshToken으로 갱신 시도');
      await refreshAccessTokenIfNeeded();
      final newData = await fetchTokenStatus(context);
      if (newData != null && newData['accessTokenValid'] == true) {
        _status = TokenStatus.fromJson(newData);
        _userEmail = await getStoredUserEmail(); // ✨ [추가] 이메일 불러오기
        await _saveToCache(newData);
        debugPrint('✅ 토큰 갱신 성공');
      } else {
        throw Exception('토큰 갱신 후에도 accessToken 유효하지 않음');
      }
    } catch (e) {
      debugPrint('❌ refreshToken으로 토큰 갱신 실패: $e');
      await clear();
    } finally {
      notifyListeners(); // ✨ [수정] 상태 변경 알림
    }
  }

  /// 상태 초기화 + 캐시 제거
  Future<void> clear() async {
    _status = null;
    _userEmail = null; // ✨ [추가] 이메일 초기화
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await clearAllTokens();
  }

  /// 강제 로그아웃 처리
  Future<void> forceLogout(BuildContext context) async {
    await clear();
    notifyListeners(); // ✨ [수정] 상태 변경을 즉시 UI에 반영
    if (context.mounted) {
      // Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Future<void> _saveToCache(Map<String, dynamic> jsonData) async {
    final prefs = await SharedPreferences.getInstance();
    final tokenStatus = TokenStatus.fromJson(jsonData);
    await prefs.setString(_cacheKey, jsonEncode(tokenStatus.toJson()));
  }
}
