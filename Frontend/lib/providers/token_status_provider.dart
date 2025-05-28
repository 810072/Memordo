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

  /// 토큰 상태 로드 (API 호출 + 캐시 저장)
  Future<void> loadStatus(BuildContext context) async {
    try {
      final data = await fetchTokenStatus(context); // API 호출
      if (data != null) {
        _status = TokenStatus.fromJson(data);
        await _saveToCache(data); // 캐시 저장
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Token status load failed: $e');
      _showErrorSnackBar(context, '토큰 상태를 불러오지 못했습니다.');
    }
  }

  /// 캐시에서 상태 불러오기
  Future<void> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_cacheKey);
    if (jsonStr != null) {
      try {
        final jsonData = jsonDecode(jsonStr);
        _status = TokenStatus.fromJson(jsonData);
        notifyListeners();
      } catch (e) {
        debugPrint('Cache decode failed: $e');
      }
    }
  }

  /// 상태 초기화 및 캐시 제거
  Future<void> clear() async {
    _status = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  /// 캐시에 저장
  Future<void> _saveToCache(Map<String, dynamic> jsonData) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(jsonData);
    await prefs.setString(_cacheKey, jsonStr);
  }

  /// 에러 스낵바 표시
  void _showErrorSnackBar(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(message), duration: Duration(seconds: 3)),
      );
    }
  }
}
