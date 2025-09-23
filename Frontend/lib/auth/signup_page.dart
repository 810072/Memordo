// lib/auth/signup_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../widgets/common_ui.dart';
import 'login_page.dart'; // 로그인 페이지로 이동하기 위해 추가

class SignUpPage extends StatefulWidget {
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  String _message = '';
  bool _isLoading = false;
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _emailVerified = false;

  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  // [수정 1] 이메일 인증 코드 발송 로직 구현
  Future<void> _sendVerificationCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      _showMessage('올바른 이메일 주소를 입력해주세요.', isError: true);
      return;
    }
    setState(() => _isSendingCode = true);

    final url = Uri.parse('$baseUrl$apiPrefix/m/send-verification');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _showMessage(data['message'] ?? '인증 코드가 이메일로 전송되었습니다.', isError: false);
      } else {
        _showMessage(data['message'] ?? '인증 코드 전송에 실패했습니다.', isError: true);
      }
    } catch (e) {
      _showMessage('인증 코드 전송 중 오류 발생: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  // [수정 2] 인증 코드 확인 로직 구현
  Future<void> _verifyCode() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showMessage('인증 코드를 입력해주세요.', isError: true);
      return;
    }
    setState(() => _isVerifyingCode = true);

    final url = Uri.parse('$baseUrl$apiPrefix/m/verify-code');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _showMessage(data['message'] ?? '이메일 인증에 성공했습니다!', isError: false);
        setState(() => _emailVerified = true);
      } else {
        _showMessage(data['message'] ?? '인증 코드가 올바르지 않습니다.', isError: true);
      }
    } catch (e) {
      _showMessage('인증 코드 확인 중 오류 발생: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isVerifyingCode = false);
    }
  }

  // [수정 3] 최종 회원가입 로직 구현
  Future<void> _signUp() async {
    if (!_emailVerified) {
      _showMessage('이메일 인증을 먼저 완료해주세요.', isError: true);
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (password.length < 6) {
      _showMessage('비밀번호는 6자 이상이어야 합니다.', isError: true);
      return;
    }
    setState(() => _isLoading = true);

    final url = Uri.parse('$baseUrl$apiPrefix/signup'); // 백엔드의 회원가입 API 엔드포인트
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        _showMessage('회원가입 성공! 로그인 페이지로 이동합니다.', isError: false);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => LoginPage()),
            (Route<dynamic> route) => false,
          );
        }
      } else {
        _showMessage(data['message'] ?? '회원가입에 실패했습니다.', isError: true);
      }
    } catch (e) {
      _showMessage('회원가입 중 오류 발생: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    setState(() => _message = msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('회원가입'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1.0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
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
                  const Text(
                    'Create Your Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 32),
                  buildTextField(
                    controller: _emailController,
                    labelText: 'Email',
                    icon: Icons.email_outlined,
                    enabled: !_emailVerified, // 인증 후 비활성화
                  ),
                  const SizedBox(height: 12),
                  buildElevatedButton(
                    text: '인증 코드 발송',
                    onPressed:
                        _emailVerified || _isSendingCode
                            ? null
                            : _sendVerificationCode,
                    isLoading: _isSendingCode,
                    bgColor: Colors.teal,
                  ),
                  const SizedBox(height: 24),
                  buildTextField(
                    controller: _codeController,
                    labelText: 'Verification Code',
                    icon: Icons.pin_outlined,
                    enabled: !_emailVerified, // 인증 후 비활성화
                  ),
                  const SizedBox(height: 12),
                  buildElevatedButton(
                    text: _emailVerified ? '인증 완료 ✓' : '인증 코드 확인',
                    onPressed:
                        _emailVerified || _isVerifyingCode ? null : _verifyCode,
                    isLoading: _isVerifyingCode,
                    bgColor: _emailVerified ? Colors.grey : Colors.teal,
                  ),
                  Divider(
                    height: 48,
                    thickness: 1,
                    color: Colors.grey.shade300,
                  ),
                  buildTextField(
                    controller: _passwordController,
                    labelText: 'Password (6자 이상)',
                    icon: Icons.lock_outline,
                    obscureText: true,
                    enabled: _emailVerified, // 인증 후에만 활성화
                  ),
                  const SizedBox(height: 32),
                  buildElevatedButton(
                    text: 'SIGN UP',
                    onPressed: !_emailVerified || _isLoading ? null : _signUp,
                    isLoading: _isLoading,
                  ),
                  if (_message.isNotEmpty && !_message.contains('성공'))
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Text(
                        _message,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
