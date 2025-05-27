import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
  } else {
    print('❌ accessToken 갱신 실패: ${response.body}');
    throw Exception('accessToken 갱신 실패');
  }
}

Future<http.Response> authorizedRequest(
  Uri url, {
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
      await refreshAccessTokenIfNeeded();
      token = await getStoredAccessToken();
      headers['Authorization'] = 'Bearer $token';
      response = await _sendRequest(method, url, headers, body);
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

Future<void> fetchSecureData() async {
  final response = await authorizedRequest(
    Uri.parse('https://aidoctorgreen.com/memo/api/secure-data'),
  );
  print('결과: ${response.body}');
}
