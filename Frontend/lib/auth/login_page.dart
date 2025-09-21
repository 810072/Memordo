// lib/auth/login_page.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_token.dart';
import '../providers/token_status_provider.dart';

import 'package:jwt_decoder/jwt_decoder.dart';
import '../services/ai_service.dart';

import '../widgets/common_ui.dart';
import 'email_check_page.dart';
import 'find_id_page.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initializeAiWithToken(String? accessToken) async {
    if (accessToken == null || accessToken.isEmpty) {
      print('⚠️ AccessToken이 없어 AI 초기화를 건너<0xEB><0x84>니다.');
      return;
    }
    try {
      Map<String, dynamic> decodedToken = JwtDecoder.decode(accessToken);
      final String? geminiApiKey = decodedToken['geminiApiKey'];

      if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
        await AiService().initializeLocalAI(geminiApiKey);
      } else {
        print('⚠️ JWT 토큰에 Gemini API 키가 없습니다.');
      }
    } catch (e) {
      print('🟥 JWT 토큰 디코딩 또는 AI 초기화 오류: $e');
    }
  }

  Future<void> _login(BuildContext context) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('이메일과 비밀번호를 입력해주세요.', isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    final url = Uri.parse('$baseUrl$apiPrefix/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['accessToken'];
        final refreshToken = data['refreshToken'];

        if (accessToken != null) await setStoredAccessToken(accessToken);
        if (refreshToken != null) await setStoredRefreshToken(refreshToken);

        await setStoredUserEmail(email);

        print('✅ 일반 로그인 성공 및 토큰/이메일 저장 완료.');

        // ✨ [추가] Provider에 로그인 성공 상태를 즉시 알립니다.
        // 로그인에 성공했으므로 토큰들이 유효하다고 가정하고 상태 객체를 만듭니다.
        final statusData = {
          'accessTokenValid': true,
          'refreshTokenValid': true,
          'googleAccessTokenValid': false, // 일반 로그인이므로 false
          'googleRefreshTokenValid': false, // 일반 로그인이므로 false
        };
        // context가 여전히 유효할 때 Provider를 업데이트합니다.
        if (mounted) {
          await Provider.of<TokenStatusProvider>(
            context,
            listen: false,
          ).updateStatus(statusData);
        }

        await _initializeAiWithToken(accessToken);

        if (mounted) {
          Navigator.pop(context); // 이전 화면으로 돌아갑니다.
        }
      } else {
        final responseBody = jsonDecode(response.body);
        final message = responseBody['message'] ?? '이메일 또는 비밀번호를 확인해주세요.';
        _showSnackBar(
          '로그인 실패: $message (${response.statusCode})',
          isError: true,
        );
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('로그인 오류: $e');
      _showSnackBar('로그인 중 오류가 발생했습니다: $e', isError: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isGoogleLoading || _isLoading) return;
    if (!mounted) return;
    setState(() => _isGoogleLoading = true);

    final clientId = dotenv.env['GOOGLE_CLIENT_ID_WEB'];
    final redirectUri = dotenv.env['REDIRECT_URI'];

    if (clientId == null ||
        clientId.isEmpty ||
        redirectUri == null ||
        redirectUri.isEmpty) {
      print(
        '❌ .env 파일에 GOOGLE_CLIENT_ID_WEB 또는 REDIRECT_URI가 올바르게 설정되지 않았습니다.',
      );
      _showSnackBar('Google 로그인 설정을 확인해주세요. (환경 변수 누락)', isError: true);
      if (mounted) setState(() => _isGoogleLoading = false);
      return;
    }

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope':
          'openid email profile https://www.googleapis.com/auth/drive.readonly',
      'access_type': 'offline',
      'prompt': 'consent',
    });

    try {
      print('🚀 Google 인증 URL 실행 시도: $authUrl');
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } else {
        print('❌ 브라우저를 열 수 없습니다: $authUrl');
        throw '브라우저를 열 수 없습니다.';
      }

      print('⏳ 인증 코드 대기 중... Redirect URI: $redirectUri');
      final code = await _waitForCode(redirectUri);

      if (code == null || code.isEmpty) {
        print('❌ Google 인증 코드를 받지 못했습니다.');
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }
      print('✅ 받은 Google 인증 code: $code');

      final response = await http
          .post(
            Uri.parse('$baseUrl$apiPrefix/google-login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Google 로그인 서버 응답: $data');

        final accessToken = data['accessToken'];
        final refreshToken = data['refreshToken'];
        final googleAccessToken = data['googleAccessToken'];
        final googleRefreshToken = data['googleRefreshToken'];
        final userEmail = data['email'];

        if (accessToken != null) await setStoredAccessToken(accessToken);
        if (refreshToken != null) await setStoredRefreshToken(refreshToken);
        if (googleAccessToken != null)
          await setStoredGoogleAccessToken(googleAccessToken);
        if (googleRefreshToken != null)
          await setStoredGoogleRefreshToken(googleRefreshToken);
        if (userEmail != null) await setStoredUserEmail(userEmail);

        print('✅ Google 로그인 성공 및 토큰/이메일 저장 완료.');

        // ✨ [추가] Provider에 로그인 성공 상태를 즉시 알립니다.
        // 서버에서 받은 토큰이 있는지 여부로 유효성을 판단하여 상태 객체를 만듭니다.
        final statusData = {
          'accessTokenValid': accessToken != null && accessToken.isNotEmpty,
          'refreshTokenValid': refreshToken != null && refreshToken.isNotEmpty,
          'googleAccessTokenValid':
              googleAccessToken != null && googleAccessToken.isNotEmpty,
          'googleRefreshTokenValid':
              googleRefreshToken != null && googleRefreshToken.isNotEmpty,
        };
        // context가 여전히 유효할 때 Provider를 업데이트합니다.
        if (mounted) {
          await Provider.of<TokenStatusProvider>(
            context,
            listen: false,
          ).updateStatus(statusData);
        }

        await _initializeAiWithToken(accessToken);

        if (mounted) {
          Navigator.pop(context); // 이전 화면으로 돌아갑니다.
        }
      } else {
        final responseBody = jsonDecode(response.body);
        final message = responseBody['message'] ?? '서버 인증에 실패했습니다.';
        _showSnackBar(
          'Google 로그인 실패: $message (${response.statusCode})',
          isError: true,
        );
        if (mounted) setState(() => _isGoogleLoading = false);
      }
    } catch (e) {
      print('⚠️ Google 로그인 중 오류 발생: $e');
      _showSnackBar('Google 로그인 중 오류가 발생했습니다: ${e.toString()}', isError: true);
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<String?> _waitForCode(String redirectUriString) async {
    HttpServer? server;
    try {
      final redirectUri = Uri.parse(redirectUriString);
      final int port = redirectUri.port;
      final expectedPath = redirectUri.path;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      print('✅ 인증 코드 대기 서버 시작 (http://${server.address.host}:$port)');

      final HttpRequest request = await server.first.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          print('❌ 인증 코드 대기 시간 초과');
          _showSnackBar('로그인 인증 시간이 초과되었습니다. 다시 시도해주세요.', isError: true);
          throw StateError('인증 코드 대기 시간 초과');
        },
      );

      if (request.uri.path != expectedPath) {
        print('❌ 잘못된 리디렉션 경로: ${request.uri.path}, 예상 경로: $expectedPath');
        request.response
          ..statusCode = 400
          ..headers.contentType = ContentType.html
          ..write('<html><body><h2>잘못된 요청 경로입니다.</h2></body></html>')
          ..close();
        await server.close(force: true);
        return null;
      }

      final String? code = request.uri.queryParameters['code'];
      final String? error = request.uri.queryParameters['error'];

      if (error != null) {
        print('❌ Google 인증 오류 콜백: $error');
        _showSnackBar('Google 인증 중 오류가 발생했습니다: $error', isError: true);
        request.response
          ..statusCode = 400
          ..headers.contentType = ContentType.html
          ..write(
            '<html><body><h2>Google 인증 오류: $error</h2><p>앱으로 돌아가 다시 시도해주세요.</p></body></html>',
          )
          ..close();
        return null;
      }

      if (code == null || code.isEmpty) {
        print('❌ 인증 코드가 전달되지 않았습니다.');
        _showSnackBar('Google로부터 인증 코드를 받지 못했습니다.', isError: true);
      } else {
        print('✅ 인증 코드 수신 완료: $code');
      }

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><head><title>인증 완료</title><style>body{font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background-color: #f0f0f0; color: #333;} div{text-align: center; padding: 20px; background-color: white; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);}</style></head><body><div><h2>✅ 인증이 완료되었습니다.</h2><p>앱으로 돌아가세요. 이 창은 곧 자동으로 닫힙니다.</p><script>setTimeout(function(){ window.close(); }, 3000);</script></div></body></html>',
        )
        ..close();
      return code;
    } catch (e) {
      print('❌ _waitForCode 실행 중 오류: $e');
      _showSnackBar('_waitForCode 오류: $e', isError: true);
      return null;
    } finally {
      if (server != null) {
        await server.close(force: true);
        print('✅ 인증 코드 대기 서버 종료');
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.redAccent.shade700 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        elevation: 4.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✨ [수정] body가 AppBar 뒤로 확장되도록 설정
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.grey[100],
      // ✨ [추가] 뒤로가기 버튼을 포함하는 AppBar 추가
      appBar: AppBar(
        backgroundColor: Colors.transparent, // 배경 투명
        elevation: 0, // 그림자 제거
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '뒤로가기',
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 5.0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Container(
              width: 400,
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.symmetric(
                horizontal: 32.0,
                vertical: 48.0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.note_alt_rounded,
                    size: 50,
                    color: Colors.deepPurple.shade300,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Memordo',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple.shade400,
                    ),
                  ),
                  const SizedBox(height: 40),
                  buildTextField(
                    controller: _emailController,
                    labelText: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    iconColor: Colors.grey.shade600,
                    fillColor: Colors.grey.shade200,
                    focusedBorderColor: Colors.deepPurple.shade300,
                  ),
                  const SizedBox(height: 16),
                  buildTextField(
                    controller: _passwordController,
                    labelText: 'Password',
                    icon: Icons.lock_outline,
                    obscureText: true,
                    onSubmitted: (_) {
                      if (!_isLoading && !_isGoogleLoading) {
                        _login(context);
                      }
                    },
                    iconColor: Colors.grey.shade600,
                    fillColor: Colors.grey.shade200,
                    focusedBorderColor: Colors.deepPurple.shade300,
                  ),
                  const SizedBox(height: 32),
                  buildElevatedButton(
                    text: 'LOGIN',
                    onPressed:
                        _isLoading || _isGoogleLoading
                            ? null
                            : () => _login(context),
                    isLoading: _isLoading,
                    bgColor: Colors.deepPurple,
                  ),
                  const SizedBox(height: 16),
                  _buildGoogleButton(
                    text: "Continue with Google",
                    onPressed:
                        _isLoading || _isGoogleLoading
                            ? null
                            : _signInWithGoogle,
                    isLoading: _isGoogleLoading,
                  ),
                  const SizedBox(height: 32),
                  _buildTextLink(
                    "Don't have an account? Sign up",
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SignUpPage()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildTextLink(
                        "아이디 찾기",
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FindIdPage()),
                        ),
                      ),
                      _buildTextLink(
                        "비밀번호 찾기",
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EmailCheckPage()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton({
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        icon:
            isLoading
                ? Container()
                : Container(
                  padding: const EdgeInsets.only(right: 0.0),
                  height: 30,
                  width: 30,
                  child: Image.asset(
                    'assets/google_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
        label:
            isLoading
                ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.grey.shade700,
                    ),
                  ),
                )
                : Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                    fontSize: 15,
                  ),
                ),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.grey.shade400),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          disabledForegroundColor: Colors.grey.shade400.withOpacity(0.38),
        ),
      ),
    );
  }

  Widget _buildTextLink(String text, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        foregroundColor: Colors.deepPurple.shade400,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
