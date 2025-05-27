import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_token.dart'; // JWT 저장용

import 'email_check_page.dart';
import 'find_id_page.dart';

class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  bool _isButtonPressed = false;

  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  Future<void> _login(BuildContext context) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('이메일과 비밀번호를 입력해주세요.');
      return;
    }

    final url = Uri.parse('$baseUrl$apiPrefix/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // 1차: 자체 토큰
        final accessToken = data['accessToken'];
        final refreshToken = data['refreshToken'];

        if (accessToken != null && refreshToken != null) {
          await setStoredAccessToken(accessToken);
          await setStoredRefreshToken(refreshToken);
          print('✅ 자체 accessToken, refreshToken 저장 완료');
        } else {
          print('⚠️ 자체 토큰 누락됨');
        }

        // 2차: 구글 토큰
        final googleAccessToken = data['googleAccessToken'];
        final googleRefreshToken = data['googleRefreshToken'];

        if (googleAccessToken != null && googleRefreshToken != null) {
          await setStoredGoogleAccessToken(googleAccessToken);
          await setStoredGoogleRefreshToken(googleRefreshToken);
          print('✅ Google accessToken, refreshToken 저장 완료');
        } else {
          print('⚠️ Google 토큰 누락됨');
        }

        Navigator.pushReplacementNamed(context, '/main');
      } else {
        print('로그인 실패: ${response.statusCode}, ${response.body}');
        _showSnackBar('로그인 실패: 이메일 또는 비밀번호를 확인해주세요.');
      }
    } catch (e) {
      print('로그인 오류: $e');
      _showSnackBar('로그인 중 오류가 발생했습니다.');
    }
  }

  Future<void> _signInWithGoogle() async {
    final clientId = dotenv.env['GOOGLE_CLIENT_ID_WEB'];
    final redirectUri = dotenv.env['REDIRECT_URI'];

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'response_type': 'code',
      'client_id': clientId!,
      'redirect_uri': redirectUri!,
      'scope':
          'openid email profile https://www.googleapis.com/auth/drive.readonly',
      'access_type': 'offline',
      'prompt': 'consent',
    });

    try {
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } else {
        throw '브라우저 열기 실패: $authUrl';
      }

      final code = await _waitForCode(redirectUri);

      // ✅ 코드 값 확인 및 로깅
      if (code == null || code.isEmpty) {
        _showSnackBar('Google 로그인 실패: code가 비어 있습니다.');
        print('❌ 받은 code가 null 또는 빈 값입니다.');
        return;
      }

      print('✅ 받은 Google 인증 code: $code');

      final response = await http.post(
        Uri.parse('$baseUrl$apiPrefix/google-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );

      if (response.statusCode == 200) {
        print('${response.body}');
        print('✅ 서버 인증 성공: ${response.body}');
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        print('❌ 서버 인증 실패: ${response.statusCode}, ${response.body}');
        _showSnackBar('Google 로그인 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('에러 코드 : ${e}');
      print('⚠️ Google 로그인 오류: $e');
      _showSnackBar('Google 로그인 중 오류 발생');
    }
  }

  Future<String?> _waitForCode(String redirectUri) async {
    final int port = Uri.parse(redirectUri).port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    print('✅ 서버가 인증 코드를 기다리는 중입니다. (http://localhost:$port)');

    final HttpRequest request = await server.first;
    final Uri uri = request.uri;
    final String? code = uri.queryParameters['code'];

    // 응답 보내기
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write('''
      <html>
        <head><title>로그인 완료</title></head>
        <body>
          <h2>✅ 로그인 처리가 완료되었습니다.</h2>
          <p>이 창은 곧 닫아주세요.</p>
        </body>
      </html>
    ''');
    await request.response.close();
    await server.close();

    if (code == null) {
      print('❌ 인증 코드가 전달되지 않았습니다.');
    } else {
      print('✅ 인증 코드 수신 완료: $code');
    }

    return code;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _triggerLoginWithAnimation() async {
    setState(() => _isButtonPressed = true);
    await Future.delayed(Duration(milliseconds: 10));
    await _login(context);
    setState(() => _isButtonPressed = false);
  }

  void _handleKey(RawKeyEvent event) {
    final key = event.logicalKey;

    if (event is RawKeyDownEvent) {
      if (_pressedKeys.contains(key)) return;
      _pressedKeys.add(key);

      if (key == LogicalKeyboardKey.enter) {
        _triggerLoginWithAnimation();
      }
    } else if (event is RawKeyUpEvent) {
      _pressedKeys.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RawKeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKey: _handleKey,
        child: Center(
          child: Container(
            width: 400,
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.cyan),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Password'),
                ),
                SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 100),
                    curve: Curves.easeInOut,
                    transform:
                        _isButtonPressed
                            ? Matrix4.translationValues(0, 2, 0)
                            : Matrix4.identity(),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        elevation: _isButtonPressed ? 2 : 6,
                        padding:
                            _isButtonPressed
                                ? EdgeInsets.symmetric(vertical: 10)
                                : EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _triggerLoginWithAnimation,
                      child: Text(
                        'LOGIN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              _isButtonPressed
                                  ? FontWeight.w600
                                  : FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _signInWithGoogle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey),
                    ),
                    child: Text("Google로 로그인"),
                  ),
                ),
                SizedBox(height: 24),
                InkWell(
                  onTap: () => Navigator.pushNamed(context, '/signup'),
                  child: Text(
                    "Don't have an account? Sign up",
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    InkWell(
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => FindIdPage()),
                          ),
                      child: Text(
                        "아이디 찾기",
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                    InkWell(
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => EmailCheckPage()),
                          ),
                      child: Text(
                        "비밀번호 찾기",
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
