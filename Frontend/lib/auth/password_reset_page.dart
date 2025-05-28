// lib/auth/password_reset_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'login_page.dart'; // 로그인 페이지로 이동하기 위함

class PasswordResetPage extends StatefulWidget {
  final String email;

  const PasswordResetPage({Key? key, required this.email}) : super(key: key);

  @override
  _PasswordResetPageState createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  String _message = '';
  bool _isCodeSending = false; // 코드 전송 API 호출 중 로딩 상태
  bool _isCodeSent = false; // 코드 전송 완료 여부
  bool _isVerifying = false; // 코드 확인 API 호출 중 로딩 상태
  bool _isCodeVerified = false; // 코드 확인 완료 여부
  bool _isResetting = false; // 비밀번호 재설정 API 호출 중 로딩 상태

  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  // 인증 코드 전송 API 호출 함수
  Future<void> _sendVerificationCode() async {
    setState(() {
      _isCodeSending = true;
      _message = ''; // 이전 메시지 초기화
    });

    final url = Uri.parse('$baseUrl$apiPrefix/m/send-verification');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _showMessage(data['message'] ?? '인증 코드가 이메일로 전송되었습니다.', isError: false);
        setState(() => _isCodeSent = true);
      } else {
        _showMessage(
          data['message'] ?? '인증 코드 전송 실패 (${response.statusCode})',
          isError: true,
        );
      }
    } catch (e) {
      _showMessage('인증 코드 전송 중 오류 발생: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isCodeSending = false);
    }
  }

  // 인증 코드 확인 API 호출 함수
  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showMessage('인증 코드를 입력해주세요.', isError: true);
      return;
    }

    setState(() {
      _isVerifying = true;
      _message = ''; // 이전 메시지 초기화
    });

    final url = Uri.parse('$baseUrl$apiPrefix/m/verify-code');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email, 'code': code}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _showMessage(data['message'] ?? '인증 코드 확인 성공!', isError: false);
        setState(() => _isCodeVerified = true);
      } else {
        _showMessage(
          data['message'] ?? '인증 코드 확인 실패 (${response.statusCode})',
          isError: true,
        );
        setState(() => _isCodeVerified = false);
      }
    } catch (e) {
      _showMessage('인증 코드 확인 중 오류 발생: $e', isError: true);
      setState(() => _isCodeVerified = false);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // 비밀번호 재설정 API 호출 함수
  Future<void> _resetPassword() async {
    final newPassword = _newPasswordController.text.trim();
    if (!_isCodeVerified) {
      _showMessage('인증 코드 확인을 먼저 완료해주세요.', isError: true);
      return;
    }
    if (newPassword.isEmpty) {
      _showMessage('새 비밀번호를 입력해주세요.', isError: true);
      return;
    }
    if (newPassword.length < 6) {
      // 간단한 유효성 검사 예시
      _showMessage('비밀번호는 6자 이상이어야 합니다.', isError: true);
      return;
    }

    setState(() {
      _isResetting = true;
      _message = ''; // 이전 메시지 초기화
    });

    final url = Uri.parse('$baseUrl$apiPrefix/reset-password');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email, 'newPassword': newPassword}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _showMessage(
          data['message'] ?? '비밀번호가 성공적으로 변경되었습니다. 로그인 페이지로 이동합니다.',
          isError: false,
        );
        await Future.delayed(const Duration(seconds: 2)); // 메시지 확인 시간
        if (mounted) {
          // 모든 이전 라우트를 제거하고 로그인 페이지로 이동
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => LoginPage()),
            (Route<dynamic> route) => false,
          );
        }
      } else {
        _showMessage(
          data['message'] ?? '비밀번호 재설정 실패 (${response.statusCode})',
          isError: true,
        );
      }
    } catch (e) {
      _showMessage('비밀번호 재설정 중 오류 발생: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    setState(() => _message = msg); // 화면 하단에 메시지 표시용
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        margin: const EdgeInsets.all(16.0),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('비밀번호 재설정'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1.0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 32.0,
                vertical: 48.0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '비밀번호 재설정',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '이메일: ${widget.email}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 32),

                  // 1단계: 인증 코드 전송
                  _buildElevatedButton(
                    text: _isCodeSent ? '인증 코드 재전송' : '인증 코드 보내기',
                    onPressed:
                        _isCodeSending || _isCodeVerified
                            ? null
                            : _sendVerificationCode, // 인증 완료 후 비활성화
                    isLoading: _isCodeSending,
                    bgColor: Colors.teal,
                  ),
                  const SizedBox(height: 24),

                  // 2단계: 인증 코드 입력 및 확인
                  _buildTextField(
                    controller: _codeController,
                    labelText: '인증 코드 입력',
                    icon: Icons.pin_outlined,
                    keyboardType: TextInputType.number,
                    enabled:
                        _isCodeSent &&
                        !_isCodeVerified &&
                        !_isVerifying, // 코드 전송 후, 인증 전, 확인 중 아닐 때 활성화
                  ),
                  const SizedBox(height: 12),
                  _buildElevatedButton(
                    text: _isCodeVerified ? '코드 확인 완료 ✓' : '코드 확인',
                    onPressed:
                        !_isCodeSent || _isCodeVerified || _isVerifying
                            ? null
                            : _verifyCode,
                    isLoading: _isVerifying,
                    bgColor:
                        _isCodeVerified
                            ? Colors.grey
                            : Colors.teal, // 인증 완료 시 회색으로 변경
                  ),

                  Divider(
                    height: 48,
                    thickness: 1,
                    color: Colors.grey.shade300,
                  ),

                  // 3단계: 새 비밀번호 입력 및 변경
                  _buildTextField(
                    controller: _newPasswordController,
                    labelText: '새 비밀번호 (6자 이상)',
                    icon: Icons.lock_reset_outlined,
                    obscureText: true,
                    enabled:
                        _isCodeVerified &&
                        !_isResetting, // 코드 확인 완료 후, 재설정 중 아닐 때 활성화
                  ),
                  const SizedBox(height: 24),
                  _buildElevatedButton(
                    text: '비밀번호 변경',
                    onPressed:
                        !_isCodeVerified || _isResetting
                            ? null
                            : _resetPassword,
                    isLoading: _isResetting,
                  ),

                  // 메시지 표시 영역 (SnackBar로 대체했으므로 선택 사항)
                  // if (_message.isNotEmpty)
                  //   Padding(
                  //     padding: const EdgeInsets.only(top: 20),
                  //     child: Text(
                  //       _message,
                  //       textAlign: TextAlign.center,
                  //       style: TextStyle(color: _message.contains('실패') || _message.contains('오류') ? Colors.redAccent : Colors.green, fontSize: 14),
                  //     ),
                  //   ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- 공통 위젯 빌더 (다른 인증 페이지에서 복사 또는 별도 파일로 분리) ---
  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.deepPurple, width: 2.0),
          borderRadius: BorderRadius.circular(8.0),
        ),
        disabledBorder: OutlineInputBorder(
          // 비활성화 시 테두리
          borderSide: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8.0),
        ),
        filled: !enabled, // 비활성화 시 배경색 채우기
        fillColor: Colors.grey.shade100,
      ),
    );
  }

  Widget _buildElevatedButton({
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
    Color bgColor = Colors.deepPurple,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          elevation: 4,
          disabledBackgroundColor: bgColor.withOpacity(0.5), // 비활성화 시 색상
        ),
        onPressed: isLoading ? null : onPressed, // 로딩 중일 때 비활성화
        child:
            isLoading
                ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
                : Text(
                  text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
      ),
    );
  }

  // --- ---
}
