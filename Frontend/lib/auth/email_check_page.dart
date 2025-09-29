// lib/auth/email_check_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../providers/status_bar_provider.dart';
import 'password_reset_page.dart';
import '../widgets/common_ui.dart';

class EmailCheckPage extends StatefulWidget {
  @override
  _EmailCheckPageState createState() => _EmailCheckPageState();
}

class _EmailCheckPageState extends State<EmailCheckPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  void _showMessage(String msg, {StatusType type = StatusType.info}) {
    if (!mounted) return;
    context.read<StatusBarProvider>().showStatusMessage(msg, type: type);
  }

  Future<void> _checkEmailAndProceed() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      _showMessage('올바른 이메일 주소를 입력해주세요.', type: StatusType.error);
      return;
    }

    setState(() => _isLoading = true);
    final url = Uri.parse('$baseUrl$apiPrefix/check-email');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (responseBody.containsKey('isDuplicate') &&
            responseBody['isDuplicate'] == true) {
          _showMessage(
            '등록된 계정을 찾았습니다. 비밀번호 재설정 페이지로 이동합니다.',
            type: StatusType.success,
          );
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PasswordResetPage(email: email),
              ),
            );
          }
        } else {
          _showMessage('해당 이메일로 등록된 계정을 찾을 수 없습니다.', type: StatusType.error);
        }
      } else {
        final errorMessage = responseBody['message'] ?? '오류가 발생했습니다.';
        _showMessage(
          '$errorMessage (${response.statusCode})',
          type: StatusType.error,
        );
      }
    } catch (e) {
      _showMessage('네트워크 오류 또는 응답 처리 오류: $e', type: StatusType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('비밀번호 찾기'),
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
                  const Text(
                    '이메일 주소 확인',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '가입 시 사용한 이메일 주소를 입력하시면\n비밀번호 재설정 페이지로 안내해 드립니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  buildTextField(
                    controller: _emailController,
                    labelText: '이메일 주소',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 24),
                  buildElevatedButton(
                    text: '이메일 확인',
                    onPressed: _isLoading ? null : _checkEmailAndProceed,
                    isLoading: _isLoading,
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
