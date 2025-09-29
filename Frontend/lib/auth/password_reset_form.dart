// lib/auth/password_reset_form.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../providers/status_bar_provider.dart';
import '../widgets/common_ui.dart';

class PasswordResetForm extends StatefulWidget {
  final String email;
  final VoidCallback onGoToLogin;

  const PasswordResetForm({
    Key? key,
    required this.email,
    required this.onGoToLogin,
  }) : super(key: key);

  @override
  _PasswordResetFormState createState() => _PasswordResetFormState();
}

class _PasswordResetFormState extends State<PasswordResetForm> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  bool _isCodeSending = false;
  bool _isCodeSent = false;
  bool _isVerifying = false;
  bool _isCodeVerified = false;
  bool _isResetting = false;

  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  void _showMessage(String msg, {StatusType type = StatusType.info}) {
    if (!mounted) return;
    context.read<StatusBarProvider>().showStatusMessage(msg, type: type);
  }

  @override
  void initState() {
    super.initState();
    _sendVerificationCode(); // 폼이 표시되자마자 코드 전송
  }

  Future<void> _sendVerificationCode() async {
    setState(() => _isCodeSending = true);
    final url = Uri.parse('$baseUrl$apiPrefix/m/send-verification');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _showMessage(
          data['message'] ?? '인증 코드가 이메일로 전송되었습니다.',
          type: StatusType.success,
        );
        setState(() => _isCodeSent = true);
      } else {
        _showMessage(data['message'] ?? '인증 코드 전송 실패', type: StatusType.error);
      }
    } catch (e) {
      _showMessage('인증 코드 전송 중 오류 발생: $e', type: StatusType.error);
    } finally {
      if (mounted) setState(() => _isCodeSending = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showMessage('인증 코드를 입력해주세요.', type: StatusType.error);
      return;
    }
    setState(() => _isVerifying = true);
    final url = Uri.parse('$baseUrl$apiPrefix/m/verify-code');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email, 'code': code}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _showMessage(
          data['message'] ?? '인증 코드 확인 성공!',
          type: StatusType.success,
        );
        setState(() => _isCodeVerified = true);
      } else {
        _showMessage(data['message'] ?? '인증 코드 확인 실패', type: StatusType.error);
      }
    } catch (e) {
      _showMessage('인증 코드 확인 중 오류 발생: $e', type: StatusType.error);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resetPassword() async {
    final newPassword = _newPasswordController.text.trim();
    if (!_isCodeVerified) {
      _showMessage('인증 코드 확인을 먼저 완료해주세요.', type: StatusType.error);
      return;
    }
    if (newPassword.length < 6) {
      _showMessage('비밀번호는 6자 이상이어야 합니다.', type: StatusType.error);
      return;
    }
    setState(() => _isResetting = true);
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
          data['message'] ?? '비밀번호가 성공적으로 변경되었습니다.',
          type: StatusType.success,
        );
        await Future.delayed(const Duration(seconds: 1));
        widget.onGoToLogin();
      } else {
        _showMessage(data['message'] ?? '비밀번호 재설정 실패', type: StatusType.error);
      }
    } catch (e) {
      _showMessage('비밀번호 재설정 중 오류 발생: $e', type: StatusType.error);
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
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
            buildElevatedButton(
              text: _isCodeSent ? '인증 코드 재전송' : '인증 코드 보내기',
              onPressed: _isCodeSending || _isCodeVerified
                  ? null
                  : _sendVerificationCode,
              isLoading: _isCodeSending,
              bgColor: Colors.teal,
            ),
            const SizedBox(height: 24),
            buildTextField(
              controller: _codeController,
              labelText: '인증 코드 입력',
              icon: Icons.pin_outlined,
              keyboardType: TextInputType.number,
              enabled: _isCodeSent && !_isCodeVerified && !_isVerifying,
            ),
            const SizedBox(height: 12),
            buildElevatedButton(
              text: _isCodeVerified ? '코드 확인 완료 ✓' : '코드 확인',
              onPressed: !_isCodeSent || _isCodeVerified || _isVerifying
                  ? null
                  : _verifyCode,
              isLoading: _isVerifying,
              bgColor: _isCodeVerified ? Colors.grey : Colors.teal,
            ),
            Divider(height: 48, thickness: 1, color: Colors.grey.shade300),
            buildTextField(
              controller: _newPasswordController,
              labelText: '새 비밀번호 (6자 이상)',
              icon: Icons.lock_reset_outlined,
              obscureText: true,
              enabled: _isCodeVerified && !_isResetting,
            ),
            const SizedBox(height: 24),
            buildElevatedButton(
              text: '비밀번호 변경',
              onPressed: !_isCodeVerified || _isResetting
                  ? null
                  : _resetPassword,
              isLoading: _isResetting,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onGoToLogin,
              child: const Text('Back to Login'),
            ),
          ],
        ),
      ),
    );
  }
}
