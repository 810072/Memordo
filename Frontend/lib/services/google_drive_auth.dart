import 'dart:async';
import 'dart:convert';
import 'dart:io'; // HttpServer 사용
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // 토큰 저장용
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GoogleDriveAuth {
  final String _clientId = dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
  final String _clientSecret = dotenv.env['GOOGLE_CLIENT_SECRET'] ?? '';

  // 요청할 권한 범위 (기존 코드와 동일)
  final List<String> _scopes = [
    'email',
    'https://www.googleapis.com/auth/drive.readonly',
  ];

  // 리디렉션 받을 로컬 주소 및 포트
  final String _redirectUri = 'http://localhost';
  final int _redirectPort = 8080; // 사용할 포트 (다른 프로그램과 겹치지 않게)

  final _storage = const FlutterSecureStorage(); // 토큰 저장을 위한 인스턴스

  HttpServer? _redirectServer; // 리디렉션을 받을 로컬 서버
  final Completer<String> _authCodeCompleter =
      Completer<String>(); // 인증 코드를 기다리기 위한 Completer

  // Access Token 가져오기 (기존 getAccessToken 대체)
  Future<String?> getAccessToken() async {
    // 1. 저장된 유효한 토큰 확인 (선택 사항: Refresh Token 로직 추가 시 유용)
    String? accessToken = await _storage.read(key: 'google_access_token');
    // TODO: 토큰 만료 시간 확인 및 Refresh Token 로직 추가

    if (accessToken != null) {
      print("저장된 Access Token 사용");
      return accessToken;
    }

    // 2. 저장된 토큰이 없으면 새로 인증 시작
    try {
      // 로컬 리디렉션 서버 시작
      await _startRedirectServer();

      // 인증 URL 생성 및 브라우저 실행
      String authUrl = _buildAuthUrl();
      if (await canLaunchUrl(Uri.parse(authUrl))) {
        await launchUrl(
          Uri.parse(authUrl),
          webOnlyWindowName: '_self',
        ); // 새 창 또는 탭에서 열기
      } else {
        throw 'Could not launch $authUrl';
      }

      // 리디렉션 서버에서 인증 코드가 수신될 때까지 대기
      print("Google 로그인을 위해 브라우저를 열었습니다. 로그인 후 이 창으로 돌아오세요...");
      String authCode = await _authCodeCompleter.future;
      print("인증 코드 수신: $authCode");

      // 리디렉션 서버 종료
      await _stopRedirectServer();

      // 3. 인증 코드를 사용하여 Access Token 및 Refresh Token 교환
      final tokens = await _exchangeCodeForTokens(authCode);

      if (tokens != null && tokens['access_token'] != null) {
        // 토큰 저장 (Secure Storage 사용 권장)
        await _storage.write(
          key: 'google_access_token',
          value: tokens['access_token'],
        );
        if (tokens['refresh_token'] != null) {
          await _storage.write(
            key: 'google_refresh_token',
            value: tokens['refresh_token'],
          );
        }
        // TODO: 만료 시간(expires_in)도 저장하여 관리

        print("Access Token 발급 성공");
        return tokens['access_token'];
      } else {
        throw 'Failed to get tokens';
      }
    } catch (e) {
      print("Google 로그인/토큰 발급 실패: $e");
      await _stopRedirectServer(); // 오류 발생 시 서버 종료
      return null;
    }
  }

  // 인증 URL 생성
  String _buildAuthUrl() {
    return 'https://accounts.google.com/o/oauth2/v2/auth?' +
        'client_id=$_clientId&' +
        'redirect_uri=$_redirectUri:$_redirectPort&' + // 리디렉션 URI에 포트 포함
        'response_type=code&' +
        'scope=${_scopes.join(' ')}&' +
        'access_type=offline'; // Refresh Token 받으려면 offline 필요
    // + '&prompt=consent'; // 필요시 사용자 동의를 다시 받도록 함
  }

  // 로컬 리디렉션 서버 시작
  Future<void> _startRedirectServer() async {
    _redirectServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _redirectPort,
    );
    print('리디렉션 서버 시작: ${_redirectServer?.address}:${_redirectServer?.port}');

    _redirectServer?.listen((HttpRequest request) async {
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      String responseMessage;
      if (code != null) {
        responseMessage = """
          <html>
            <head><title>인증 성공</title></head>
            <body>
              <h1>인증 성공!</h1>
              <p>앱으로 돌아가세요.</p>
              <script>window.close();</script> </body>
          </html>
          """;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(responseMessage);
        await request.response.close();
        if (!_authCodeCompleter.isCompleted) {
          _authCodeCompleter.complete(code); // Completer에 인증 코드 전달
        }
      } else if (error != null) {
        responseMessage = """
          <html>
            <head><title>인증 실패</title></head>
            <body><h1>인증 실패</h1><p>오류: $error</p><p>앱으로 돌아가세요.</p></body>
          </html>
          """;
        request.response
          ..statusCode =
              HttpStatus
                  .ok // 오류여도 일단 200으로 응답해야 브라우저에 표시됨
          ..headers.contentType = ContentType.html
          ..write(responseMessage);
        await request.response.close();
        if (!_authCodeCompleter.isCompleted) {
          _authCodeCompleter.completeError(Exception('OAuth error: $error'));
        }
      } else {
        // 예상치 못한 요청
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('잘못된 요청입니다.');
        await request.response.close();
      }
    });
  }

  // 로컬 리디렉션 서버 중지
  Future<void> _stopRedirectServer() async {
    await _redirectServer?.close(force: true);
    _redirectServer = null;
    print('리디렉션 서버 중지됨');
    // Completer가 완료되지 않았다면 에러로 완료 처리 (타임아웃 등)
    if (!_authCodeCompleter.isCompleted) {
      _authCodeCompleter.completeError(Exception("인증 응답을 받지 못했습니다."));
    }
  }

  // 인증 코드로 토큰 교환
  Future<Map<String, dynamic>?> _exchangeCodeForTokens(String code) async {
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _clientId,
        'client_secret': _clientSecret, // 데스크톱 앱의 경우 필요
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri':
            '$_redirectUri:$_redirectPort', // 인증 요청 시 사용한 리디렉션 URI와 동일해야 함
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      print('토큰 교환 실패: ${response.statusCode}');
      print('응답 본문: ${response.body}');
      return null;
    }
  }

  // TODO: Refresh Token을 사용하여 Access Token 갱신하는 로직 추가
  Future<String?> refreshAccessToken() async {
    final refreshToken = await _storage.read(key: 'google_refresh_token');
    if (refreshToken == null) {
      print("Refresh Token 없음. 재로그인 필요.");
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode == 200) {
        final tokens = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = tokens['access_token'];
        await _storage.write(key: 'google_access_token', value: newAccessToken);
        // TODO: 새로 발급된 토큰의 만료 시간 업데이트
        print("Access Token 갱신 성공");
        return newAccessToken;
      } else {
        print('토큰 갱신 실패: ${response.statusCode}');
        print('응답 본문: ${response.body}');
        // Refresh Token이 만료되었거나 문제가 있는 경우, 저장된 토큰 삭제 및 재로그인 유도
        await logout();
        return null;
      }
    } catch (e) {
      print("토큰 갱신 중 오류: $e");
      return null;
    }
  }

  // 로그아웃 (저장된 토큰 삭제)
  Future<void> logout() async {
    await _storage.delete(key: 'google_access_token');
    await _storage.delete(key: 'google_refresh_token');
    // TODO: 저장된 만료 시간 등 다른 정보도 삭제
    print("로그아웃: 저장된 토큰 삭제 완료");
  }
}
