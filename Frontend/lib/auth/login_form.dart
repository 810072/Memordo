// lib/auth/login_form.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../services/auth_token.dart';
import '../providers/token_status_provider.dart';
import '../services/ai_service.dart';
import '../providers/status_bar_provider.dart';
import '../widgets/common_ui.dart';

class LoginForm extends StatefulWidget {
  final VoidCallback onGoToSignup;
  final VoidCallback onGoToFindId;
  final VoidCallback onGoToEmailCheck;

  const LoginForm({
    Key? key,
    required this.onGoToSignup,
    required this.onGoToFindId,
    required this.onGoToEmailCheck,
  }) : super(key: key);

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
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

  void _showMessage(String msg, {StatusType type = StatusType.info}) {
    if (!mounted) return;
    context.read<StatusBarProvider>().showStatusMessage(msg, type: type);
  }

  Future<void> _initializeAiWithToken(String? accessToken) async {
    if (accessToken == null || accessToken.isEmpty) return;
    try {
      Map<String, dynamic> decodedToken = JwtDecoder.decode(accessToken);
      final String? geminiApiKey = decodedToken['geminiApiKey'];
      if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
        await AiService().initializeLocalAI(geminiApiKey);
      }
    } catch (e) {
      debugPrint('JWT 토큰 디코딩 또는 AI 초기화 오류: $e');
    }
  }

  Future<void> _login(BuildContext context) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showMessage('이메일과 비밀번호를 입력해주세요.', type: StatusType.error);
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

        final statusData = {
          'accessTokenValid': true,
          'refreshTokenValid': true,
          'googleAccessTokenValid': false,
          'googleRefreshTokenValid': false,
        };
        if (mounted) {
          await context.read<TokenStatusProvider>().updateStatus(statusData);
          await _initializeAiWithToken(accessToken);
          Navigator.pop(context);
        }
      } else {
        final responseBody = jsonDecode(response.body);
        final message = responseBody['message'] ?? '이메일 또는 비밀번호를 확인해주세요.';
        _showMessage('로그인 실패: $message', type: StatusType.error);
      }
    } catch (e) {
      _showMessage('로그인 중 오류가 발생했습니다: $e', type: StatusType.error);
    } finally {
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
      _showMessage(
        'Google 로그인 설정을 확인해주세요. (.env 파일 누락)',
        type: StatusType.error,
      );
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
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } else {
        throw '브라우저를 열 수 없습니다.';
      }

      final code = await _waitForCode(redirectUri);
      if (code == null || code.isEmpty) {
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl$apiPrefix/google-login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

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

        final statusData = {
          'accessTokenValid': accessToken != null && accessToken.isNotEmpty,
          'refreshTokenValid': refreshToken != null && refreshToken.isNotEmpty,
          'googleAccessTokenValid':
              googleAccessToken != null && googleAccessToken.isNotEmpty,
          'googleRefreshTokenValid':
              googleRefreshToken != null && googleRefreshToken.isNotEmpty,
        };

        if (mounted) {
          await context.read<TokenStatusProvider>().updateStatus(statusData);
          await _initializeAiWithToken(accessToken);
          Navigator.pop(context);
        }
      } else {
        final responseBody = jsonDecode(response.body);
        _showMessage(
          'Google 로그인 실패: ${responseBody['message'] ?? '서버 인증 실패'}',
          type: StatusType.error,
        );
      }
    } catch (e) {
      _showMessage('Google 로그인 중 오류가 발생했습니다: $e', type: StatusType.error);
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<String?> _waitForCode(String redirectUriString) async {
    HttpServer? server;
    try {
      final redirectUri = Uri.parse(redirectUriString);
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        redirectUri.port,
      );
      final request = await server.first.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          _showMessage(
            '로그인 인증 시간이 초과되었습니다. 다시 시도해주세요.',
            type: StatusType.error,
          );
          throw StateError('Timeout');
        },
      );
      final code = request.uri.queryParameters['code'];
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body><h2>✅ 인증이 완료되었습니다.</h2><p>앱으로 돌아가세요. 이 창은 곧 자동으로 닫힙니다.</p><script>setTimeout(function(){ window.close(); }, 1500);</script></body></html>',
        )
        ..close();
      return code;
    } catch (e) {
      debugPrint("인증 코드 대기 중 오류: $e");
      return null;
    } finally {
      await server?.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      color: Colors.white.withOpacity(0.95),
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
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
            ),
            const SizedBox(height: 16),
            buildTextField(
              controller: _passwordController,
              labelText: 'Password',
              icon: Icons.lock_outline,
              obscureText: true,
              onSubmitted: (_) {
                if (!_isLoading && !_isGoogleLoading) _login(context);
              },
            ),
            const SizedBox(height: 32),
            buildElevatedButton(
              text: 'LOGIN',
              onPressed:
                  _isLoading || _isGoogleLoading ? null : () => _login(context),
              isLoading: _isLoading,
              bgColor: Colors.deepPurple,
            ),
            const SizedBox(height: 16),
            _buildGoogleButton(
              text: "Continue with Google",
              onPressed:
                  _isLoading || _isGoogleLoading ? null : _signInWithGoogle,
              isLoading: _isGoogleLoading,
            ),
            const SizedBox(height: 32),
            _buildTextLink(
              "Don't have an account? Sign up",
              widget.onGoToSignup,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTextLink("아이디 찾기", widget.onGoToFindId),
                _buildTextLink("비밀번호 찾기", widget.onGoToEmailCheck),
              ],
            ),
          ],
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
        ),
      ),
    );
  }

  // ✨ [수정] TextButton 대신 InkWell과 Container를 사용하여 직접 밑줄을 그립니다.
  Widget _buildTextLink(String text, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        // 밑줄을 Container의 하단 테두리로 구현
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade600, width: 1.0),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
