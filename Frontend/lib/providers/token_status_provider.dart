import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../model/token_status_model.dart';
import '../services/auth_token.dart';

class TokenStatusProvider with ChangeNotifier {
  static const _cacheKey = 'token_status_cache';

  TokenStatus? _status;

  TokenStatus? get status => _status;

  bool get isLoaded => _status != null;
  bool get isAuthenticated => _status?.accessTokenValid == true;
  bool get isGoogleLinked => _status?.isGoogleLinked == true;

  /// 서버 + 캐시 통합 상태 확인
  Future<void> loadStatus(BuildContext context) async {
    try {
      final data = await fetchTokenStatus(context);
      if (data != null && data['accessTokenValid'] == true) {
        _status = TokenStatus.fromJson(data);
        await _saveToCache(data);
        notifyListeners();
      } else {
        await tryRefreshToken(context); // accessToken 만료 시 refresh 시도
      }
    } catch (e) {
      debugPrint('❌ Token status check failed: $e');
      await clear(); // 서버 오류 시 초기화 (로그아웃 취급)
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
        if (cached.accessTokenValid) {
          _status = cached;
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
      await refreshAccessTokenIfNeeded(); // 서버 요청 포함
      final newData = await fetchTokenStatus(context);
      if (newData != null && newData['accessTokenValid'] == true) {
        _status = TokenStatus.fromJson(newData);
        await _saveToCache(newData);
        notifyListeners();
        debugPrint('✅ 토큰 갱신 성공');
      } else {
        throw Exception('토큰 갱신 후에도 accessToken 유효하지 않음');
      }
    } catch (e) {
      debugPrint('❌ refreshToken으로 토큰 갱신 실패: $e');
      await clear();
    }
  }

  /// 상태 초기화 + 캐시 제거
  Future<void> clear() async {
    _status = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await clearAllTokens(); // secure_storage 토큰들도 함께 삭제
  }

  /// 강제 로그아웃 처리
  Future<void> forceLogout(BuildContext context) async {
    await clear();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Future<void> _saveToCache(Map<String, dynamic> jsonData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(jsonData));
  }
}
