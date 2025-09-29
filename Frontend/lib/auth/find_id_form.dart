// lib/auth/find_id_form.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../providers/status_bar_provider.dart';
import '../widgets/common_ui.dart';

class FindIdForm extends StatefulWidget {
  final VoidCallback onGoToLogin;
  const FindIdForm({Key? key, required this.onGoToLogin}) : super(key: key);

  @override
  _FindIdFormState createState() => _FindIdFormState();
}

class _FindIdFormState extends State<FindIdForm> {
  final TextEditingController _emailController = TextEditingController();
  String _resultMessage = '';
  bool _isLoading = false;

  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  void _showMessage(String msg, {StatusType type = StatusType.info}) {
    if (!mounted) return;
    context.read<StatusBarProvider>().showStatusMessage(msg, type: type);
  }

  Future<void> _findId(BuildContext context) async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      setState(() => _resultMessage = '올바른 이메일 주소를 입력해주세요.');
      _showMessage(_resultMessage, type: StatusType.error);
      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = '';
    });

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
            responseBody['isDuplicate'] is bool) {
          bool isDuplicate = responseBody['isDuplicate'];
          setState(() {
            if (isDuplicate) {
              _resultMessage = '✅ 해당 이메일로 등록된 계정이 있습니다.';
              _showMessage('등록된 계정을 확인했습니다.', type: StatusType.success);
            } else {
              _resultMessage = '❌ 해당 이메일로 등록된 계정을 찾을 수 없습니다.';
              _showMessage('등록된 계정이 없습니다.', type: StatusType.error);
            }
          });
        } else {
          setState(() => _resultMessage = '알 수 없는 API 응답 형식입니다.');
          _showMessage(_resultMessage, type: StatusType.error);
        }
      } else {
        final errorMessage = responseBody['message'] ?? '아이디 찾기에 실패했습니다.';
        setState(
          () => _resultMessage = '오류: $errorMessage (${response.statusCode})',
        );
        _showMessage(_resultMessage, type: StatusType.error);
      }
    } catch (e) {
      setState(() => _resultMessage = '네트워크 오류: $e');
      _showMessage(_resultMessage, type: StatusType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              '아이디 찾기',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '가입 시 사용한 이메일 주소를 입력해주세요.\n계정 존재 유무를 알려드립니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            if (_resultMessage.isNotEmpty && !_isLoading)
              Container(
                padding: const EdgeInsets.all(12.0),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _resultMessage.contains('✅')
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(
                    color: _resultMessage.contains('✅')
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Text(
                  _resultMessage,
                  style: TextStyle(
                    fontSize: 14,
                    color: _resultMessage.contains('✅')
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            buildTextField(
              controller: _emailController,
              labelText: '등록된 이메일 주소',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 24),
            buildElevatedButton(
              text: '아이디 찾기',
              onPressed: _isLoading ? null : () => _findId(context),
              isLoading: _isLoading,
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
