import 'package:flutter/material.dart'; // ✅ Navigator, BuildContext 사용 시 필수!
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

final _storage = FlutterSecureStorage();

Future<void> setStoredAccessToken(String token) async {
  await _storage.write(key: 'access_token', value: token);
}

Future<String?> getStoredAccessToken() async {
  return await _storage.read(key: 'access_token');
}

Future<void> setStoredRefreshToken(String token) async {
  await _storage.write(key: 'refresh_token', value: token);
}

Future<String?> getStoredRefreshToken() async {
  return await _storage.read(key: 'refresh_token');
}

Future<void> setStoredGoogleAccessToken(String token) async {
  await _storage.write(key: 'google_access_token', value: token);
}

Future<void> setStoredGoogleRefreshToken(String token) async {
  await _storage.write(key: 'google_refresh_token', value: token);
}

Future<String?> getStoredGoogleAccessToken() async {
  return await _storage.read(key: 'google_access_token');
}

Future<String?> getStoredGoogleRefreshToken() async {
  return await _storage.read(key: 'google_refresh_token');
}

Future<String?> getStoredGoogleTokenExpiry() async {
  return await _storage.read(key: 'google_token_expiry');
}

Future<void> clearAllTokens() async {
  await _storage.delete(key: 'access_token');
  await _storage.delete(key: 'refresh_token');
  await _storage.delete(key: 'google_access_token');
  await _storage.delete(key: 'google_refresh_token');

  print('🧹 모든 토큰 삭제 완료');
}

Future<void> refreshAccessTokenIfNeeded() async {
  final refreshToken = await getStoredRefreshToken();
  if (refreshToken == null) {
    throw Exception('리프레시 토큰이 없습니다.');
  }

  final response = await http.post(
    Uri.parse('https://aidoctorgreen.com/memo/api/refresh-token'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'refreshToken': refreshToken}),
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final newAccessToken = data['accessToken'];
    final newRefreshToken = data['refreshToken'];

    if (newAccessToken != null) {
      await setStoredAccessToken(newAccessToken);
    }
    if (newRefreshToken != null) {
      await setStoredRefreshToken(newRefreshToken);
    }

    print('✅ accessToken 갱신 성공');
  } else if (response.statusCode == 403) {
    // 🔴 리프레시 토큰 만료 또는 위조
    print('🔴 refreshToken 만료됨 → 로그아웃 필요');
    throw Exception('refreshToken 만료');
  } else {
    print('❌ accessToken 갱신 실패: ${response.body}');
    throw Exception('accessToken 갱신 실패');
  }
}

Future<http.Response> authorizedRequest(
  Uri url, {
  required BuildContext context, // ✅ context 추가
  String method = 'GET',
  Map<String, String>? headers,
  Object? body,
}) async {
  String? token = await getStoredAccessToken();

  headers ??= {};
  headers['Content-Type'] = 'application/json';
  if (token != null) {
    headers['Authorization'] = 'Bearer $token';
  }

  http.Response response;

  try {
    response = await _sendRequest(method, url, headers, body);
    if (response.statusCode == 401) {
      // accessToken 만료 → refresh 시도
      try {
        await refreshAccessTokenIfNeeded();
        token = await getStoredAccessToken();
        headers['Authorization'] = 'Bearer $token';
        response = await _sendRequest(method, url, headers, body);
      } catch (e) {
        print('❌ refreshToken도 만료됨 → 로그아웃');
        await logoutUser(context); // ✅ 자동 로그아웃
        rethrow;
      }
    }
  } catch (e) {
    print('❌ 요청 실패: $e');
    rethrow;
  }

  return response;
}

Future<http.Response> _sendRequest(
  String method,
  Uri url,
  Map<String, String>? headers,
  Object? body,
) {
  switch (method.toUpperCase()) {
    case 'POST':
      return http.post(url, headers: headers, body: body);
    case 'PUT':
      return http.put(url, headers: headers, body: body);
    case 'DELETE':
      return http.delete(url, headers: headers, body: body);
    default:
      return http.get(url, headers: headers);
  }
}

Future<void> fetchSecureData(BuildContext context) async {
  final response = await authorizedRequest(
    Uri.parse('https://aidoctorgreen.com/memo/api/secure-data'),
    context: context,
  );
  print('결과: ${response.body}');
}

Future<bool> hasValidTokens() async {
  final accessToken = await getStoredAccessToken();
  final refreshToken = await getStoredRefreshToken();
  return (accessToken != null && accessToken.isNotEmpty) ||
      (refreshToken != null && refreshToken.isNotEmpty);
}

Future<bool> tryAutoLogin() async {
  final accessToken = await getStoredAccessToken();

  if (accessToken != null && accessToken.isNotEmpty) {
    return true; // accessToken 존재 시 바로 로그인 처리
  }

  final refreshToken = await getStoredRefreshToken();
  if (refreshToken == null || refreshToken.isEmpty) {
    return false;
  }

  // refreshToken으로 accessToken 갱신 시도
  try {
    await refreshAccessTokenIfNeeded(); // 실패 시 예외 발생
    final newToken = await getStoredAccessToken();
    return newToken != null && newToken.isNotEmpty;
  } catch (e) {
    print('🔒 자동 로그인 실패: $e');
    return false;
  }
}

Future<Map<String, dynamic>?> fetchTokenStatus(BuildContext context) async {
  try {
    final response = await authorizedRequest(
      Uri.parse('https://aidoctorgreen.com/memo/api/token/status'),
      context: context, // ✅ context 추가
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data;
    } else {
      print('❌ 토큰 상태 불러오기 실패: ${response.statusCode}');
      return null;
    }
  } catch (e) {
    print('❌ 오류: $e');
    return null;
  }
}

Future<void> logoutUser(BuildContext context) async {
  await clearAllTokens(); // 모든 토큰 삭제

  if (context.mounted) {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<bool> hasValidGoogleAccessToken() async {
    final accessToken = await getStoredGoogleAccessToken();
    final expiryRaw = await _storage.read(key: 'google_token_expiry');

    if (accessToken == null || accessToken.isEmpty || expiryRaw == null) {
      return false;
    }

    final expiry = DateTime.tryParse(expiryRaw);
    if (expiry == null) return false;

    return DateTime.now().isBefore(expiry); // 유효 시간 이내
  }
}

Future<void> refreshGoogleAccessTokenIfNeeded() async {
  final expiryRaw = await _storage.read(key: 'google_token_expiry');
  final refreshToken = await getStoredGoogleRefreshToken();

  if (refreshToken == null || expiryRaw == null) {
    print('⚠️ 구글 리프레시 토큰 또는 만료 시간이 없습니다.');
    return;
  }

  final expiry = DateTime.tryParse(expiryRaw);
  if (expiry == null || DateTime.now().isBefore(expiry)) {
    print('✅ 아직 구글 access token이 유효합니다.');
    return;
  }

  final response = await http.post(
    Uri.parse('https://oauth2.googleapis.com/token'),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: {
      'client_id': dotenv.env['GOOGLE_CLIENT_ID']!,
      'client_secret': dotenv.env['GOOGLE_CLIENT_SECRET']!,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    },
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final newAccessToken = data['access_token'];
    final expiresIn = data['expires_in'];
    final expiryDate = DateTime.now().add(Duration(seconds: expiresIn));

    await setStoredGoogleAccessToken(newAccessToken);
    await _storage.write(
      key: 'google_token_expiry',
      value: expiryDate.toIso8601String(),
    );

    print('🔄 Google access token 자동 갱신 성공');
  } else {
    print('❌ Google 토큰 갱신 실패: ${response.statusCode}, ${response.body}');
    throw Exception('Google access token 재발급 실패');
  }
}
