// lib/auth/signup_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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

  // ... (_sendVerificationCode, _verifyCode, _signUp 함수 유지, _showMessage 수정) ...
  Future<void> _sendVerificationCode() async {
    /* ... */
  }
  Future<void> _verifyCode() async {
    /* ... */
  }
  Future<void> _signUp() async {
    /* ... */
  }

  void _showMessage(String msg, {bool isError = false}) {
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
                  _buildTextField(
                    controller: _emailController,
                    labelText: 'Email',
                    icon: Icons.email_outlined,
                    enabled: !_emailVerified,
                  ),
                  const SizedBox(height: 12),
                  _buildElevatedButton(
                    text: '인증 코드 발송',
                    onPressed:
                        _emailVerified || _isSendingCode
                            ? null
                            : _sendVerificationCode,
                    isLoading: _isSendingCode,
                    bgColor: Colors.teal,
                  ),
                  const SizedBox(height: 24),
                  _buildTextField(
                    controller: _codeController,
                    labelText: 'Verification Code',
                    icon: Icons.pin_outlined,
                    enabled: !_emailVerified,
                  ),
                  const SizedBox(height: 12),
                  _buildElevatedButton(
                    text: '인증 코드 확인',
                    onPressed:
                        _emailVerified || _isVerifyingCode ? null : _verifyCode,
                    isLoading: _isVerifyingCode,
                    bgColor: Colors.teal,
                  ),
                  Divider(
                    height: 48,
                    thickness: 1,
                    color: Colors.grey.shade300,
                  ),
                  _buildTextField(
                    controller: _passwordController,
                    labelText: 'Password',
                    icon: Icons.lock_outline,
                    obscureText: true,
                    enabled: _emailVerified,
                  ),
                  const SizedBox(height: 32),
                  _buildElevatedButton(
                    text: 'SIGN UP',
                    onPressed: !_emailVerified || _isLoading ? null : _signUp,
                    isLoading: _isLoading,
                  ),
                  if (_message.isNotEmpty &&
                      !_message.contains('성공')) // 성공 메시지는 SnackBar로만 표시
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

  // --- 공통 위젯 빌더 ---
  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    /* ... */
    return TextField(/* ... */);
  }

  Widget _buildElevatedButton({
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
    Color bgColor = Colors.deepPurple,
  }) {
    /* ... */
    return SizedBox(/* ... */);
  }

  // --- ---
}
