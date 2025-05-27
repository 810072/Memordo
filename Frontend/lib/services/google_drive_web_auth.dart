// lib/services/google_drive_web_auth.dart
// Google Drive 인증 구현 (웹 전용)

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // 웹 전용 라이브러리
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Secure Storage (웹에서는 localStorage 기반)
const _storage = FlutterSecureStorage();

// 팝업 창 객체 전역 관리
html.WindowBase? _authPopup;

class GoogleDriveAuth {
  final String _clientId = dotenv.env['GOOGLE_CLIENT_ID_WEB'] ?? '';

  // 요청할 권한 범위
  final List<String> _scopes = [
    'email',
    'https://www.googleapis.com/auth/drive.readonly',
  ];

  // 리디렉션 경로 및 URI 설정
  final String _redirectPath = '/callback';

  final String _redirectUri = html.window.location.origin + '/callback';

  // 인증 흐름 결과를 기다리기 위한 Completer
  Completer<String>? _authCompleter;

  // 메시지 수신 리스너
  late html.EventListener _messageEventListener;

  // 생성자에서 리스너 설정
  GoogleDriveAuth() {
    print('[GoogleDriveAuth] Redirect URI: $_redirectUri');

    // OAuth 팝업으로부터 메시지 받는 리스너
    _messageEventListener = (html.Event event) {
      if (event is html.MessageEvent) {
        final data = event.data;
        print('✅ OAuth 응답 수신 from: ${event.origin}');
        print('🔹 Data: $data');

        // 응답이 URL fragment 형태인지 확인
        if (data is String && (data.startsWith('#') || data.startsWith('?'))) {
          try {
            final uri = Uri.parse('http://dummy.com/' + data);
            final params =
                data.startsWith('#')
                    ? Uri.splitQueryString(uri.fragment)
                    : uri.queryParameters;

            final accessToken = params['access_token'];
            final error = params['error'];

            if (accessToken != null) {
              print('🔐 Access Token 수신 완료');
              _handleTokenReceived(accessToken);
              _authCompleter?.complete(accessToken);
            } else if (error != null) {
              print('⚠️ OAuth 오류 발생: $error');
              _authCompleter?.completeError(Exception('OAuth error: $error'));
            } else {
              final code = params['code'];
              if (code != null) {
                print('📥 Authorization Code 수신 (토큰 교환 필요): $code');
                _authCompleter?.completeError(
                  UnimplementedError('Code flow 미구현. Code: $code'),
                );
              } else {
                _authCompleter?.completeError(Exception('❌ 예기치 않은 OAuth 응답'));
              }
            }
          } catch (e) {
            print('🧨 OAuth 응답 파싱 실패: $e');
            _authCompleter?.completeError(Exception('OAuth 응답 처리 중 오류: $e'));
          } finally {
            _authPopup?.close();
            _authPopup = null;
            html.window.removeEventListener('message', _messageEventListener);
          }
        }
      }
    };

    // 이벤트 리스너 등록
    html.window.addEventListener('message', _messageEventListener);
  }

  /// 위젯 dispose 시 호출
  void dispose() {
    print('[GoogleDriveAuth] 리스너 제거 및 팝업 종료');
    html.window.removeEventListener('message', _messageEventListener);
    _authPopup?.close();
    _authPopup = null;
  }

  /// Access Token을 반환하거나 로그인 진행
  Future<String?> getAccessToken() async {
    final token = await _storage.read(key: 'google_access_token');
    print("토큰!!!!!!!! :");
    print(token);

    if (token != null && token.isNotEmpty) {
      print('[GoogleDriveAuth] 저장된 토큰 사용');
      return token;
    }

    print('[GoogleDriveAuth] 저장된 토큰 없음 → 로그인 진행');

    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      print('[GoogleDriveAuth] 기존 인증 플로우 대기 중');
      return _authCompleter!.future.catchError((e) {
        print('[GoogleDriveAuth] 기존 인증 실패: $e');
        return null;
      });
    }

    _authCompleter = Completer<String>();

    final authUrl =
        'https://accounts.google.com/o/oauth2/v2/auth?'
        'client_id=$_clientId&'
        'redirect_uri=${Uri.encodeComponent(_redirectUri)}&'
        'response_type=token&'
        'scope=${Uri.encodeComponent(_scopes.join(' '))}&'
        'include_granted_scopes=true';

    _authPopup = html.window.open(
      authUrl,
      'GoogleSignIn',
      'width=500,height=600,resizable=yes,scrollbars=yes',
    );

    if (_authPopup == null) {
      print('[GoogleDriveAuth] 팝업 차단됨');
      _authCompleter?.completeError(
        Exception('팝업 창을 열 수 없습니다. 팝업 차단을 해제해주세요.'),
      );
      return null;
    }

    // 팝업 창 닫힘 감지 타이머
    Timer? popupCheckTimer;
    popupCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (_authPopup != null && _authPopup!.closed!) {
        timer.cancel();
        print('[GoogleDriveAuth] 팝업 수동 종료됨');
        _authCompleter?.completeError(Exception('인증 창이 닫혔습니다.'));
        _authPopup = null;
        html.window.removeEventListener('message', _messageEventListener);
      }

      if (_authCompleter!.isCompleted) {
        timer.cancel();
        _authPopup = null;
      }
    });

    try {
      return await _authCompleter!.future;
    } catch (e) {
      print('[GoogleDriveAuth] 인증 실패: $e');
      _authPopup?.close();
      _authPopup = null;
      html.window.removeEventListener('message', _messageEventListener);
      return null;
    } finally {
      popupCheckTimer?.cancel();
    }
  }

  /// 토큰 저장
  void _handleTokenReceived(String accessToken) {
    print('[GoogleDriveAuth] 토큰 저장 중: $accessToken');
    _storage.write(key: 'google_access_token', value: accessToken);
  }

  /// 웹에서는 refresh token 없음
  Future<String?> refreshAccessToken() async {
    print('[GoogleDriveAuth] 웹에서는 토큰 갱신 불가 (Implicit Flow)');
    return null;
  }

  /// 로그아웃 (저장된 토큰 삭제)
  Future<void> logout() async {
    print('[GoogleDriveAuth] 로그아웃: 저장된 토큰 삭제');
    await _storage.delete(key: 'google_access_token');
    await _storage.delete(key: 'google_refresh_token');
  }
}
