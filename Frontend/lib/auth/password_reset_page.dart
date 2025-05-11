// password_reset_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'login_page.dart';

// 비밀번호 재설정 페이지 위젯
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
  bool _isCodeSent = false;
  bool _isCodeVerified = false;

  // API 기본 URL (실제 서버 주소로 변경 필요)
  final String baseUrl = 'https://aidoctorgreen.com'; // 예시 URL
  // API 경로 접두사
  final String apiPrefix = '/memo/api';

  // 인증 코드 전송 API 호출 함수
  Future<void> _sendVerificationCode() async {
    final url = Uri.parse('$baseUrl$apiPrefix/m/send-verification');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _message = data['message'] ?? '인증 코드가 이메일로 전송되었습니다.';
          _isCodeSent = true;
        });
        print('인증 코드 전송 성공: ${response.body}');
      } else {
        setState(() {
          _message = data['message'] ?? '인증 코드 전송 실패';
        });
        print('인증 코드 전송 실패: ${response.statusCode}, ${response.body}');
      }
    } catch (e) {
      setState(() {
        _message = '인증 코드 전송 오류: $e';
      });
      print('인증 코드 전송 오류: $e');
    }
  }

  // 인증 코드 확인 API 호출 함수
  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      setState(() => _message = '인증 코드를 입력해주세요.');
      return;
    }

    final url = Uri.parse('$baseUrl$apiPrefix/m/verify-code');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': widget.email, 'code': code}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _message = data['message'] ?? '인증 코드 확인 성공';
          _isCodeVerified = true; // 코드 확인 성공 상태 업데이트
        });
        print('인증 코드 확인 성공: ${response.body}');
      } else {
        setState(() {
          _message = data['message'] ?? '인증 코드 확인 실패';
          _isCodeVerified = false;
        });
        print('인증 코드 확인 실패: ${response.statusCode}, ${response.body}');
      }
    } catch (e) {
      setState(() {
        _message = '인증 코드 확인 오류: $e';
        _isCodeVerified = false;
      });
      print('인증 코드 확인 오류: $e');
    }
  }

  // 비밀번호 재설정 API 호출 함수
  Future<void> _resetPassword() async {
    final newPassword = _newPasswordController.text.trim();

    if (!_isCodeVerified) {
      setState(() => _message = '인증 코드 확인을 먼저 완료해주세요.');
      return;
    }

    if (newPassword.isEmpty) {
      setState(() => _message = '새 비밀번호를 입력해주세요.');
      return;
    }

    final url = Uri.parse('$baseUrl$apiPrefix/reset-password');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        // ✅ 요청 본문에서 'code' 필드 제거, 이메일과 새 비밀번호만 포함
        body: jsonEncode({'email': widget.email, 'newPassword': newPassword}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // ✅ 비밀번호 재설정 성공
        setState(() {
          _message = data['message'] ?? '비밀번호가 성공적으로 변경되었습니다.';
        });
        print('비밀번호 재설정 성공: ${response.body}');

        // TODO: 비밀번호 변경 성공 후 로그인 페이지 등으로 이동
        // Navigator.pushReplacementNamed(context, '/login'); // 로그인 페이지로 이동 예시
      } else {
        // 비밀번호 재설정 실패
        setState(() {
          _message = data['message'] ?? '비밀번호 재설정 실패';
        });
        print('비밀번호 재설정 실패: ${response.statusCode}, ${response.body}');
      }
    } catch (e) {
      // 네트워크 오류 등 예외 발생
      setState(() {
        _message = '비밀번호 재설정 오류: $e';
      });
      print('비밀번호 재설정 오류: $e');
    }
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
      appBar: AppBar(
        title: Text('비밀번호 재설정'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Center(
        child: Container(
          width: 400,
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '이메일: ${widget.email}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isCodeSent ? null : _sendVerificationCode,
                child: Text(_isCodeSent ? '코드 전송 완료' : '인증 코드 보내기'),
              ),
              SizedBox(height: 16),

              TextField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: '인증 코드 입력',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                enabled: _isCodeSent && !_isCodeVerified,
              ),
              SizedBox(height: 16),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                // 코드 전송되었고 아직 확인되지 않았을 때만 버튼 활성화
                onPressed:
                    (_isCodeSent && !_isCodeVerified) ? _verifyCode : null,
                child: Text(_isCodeVerified ? '코드 확인 완료' : '코드 확인'),
              ),
              SizedBox(height: 24),

              TextField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '새 비밀번호',
                  border: OutlineInputBorder(),
                ),
                enabled: _isCodeVerified, // 코드 확인 완료 후에만 활성화
              ),
              SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  // 코드 확인 완료 후에만 버튼 활성화
                  onPressed: _isCodeVerified ? _resetPassword : null,
                  child: Text('비밀번호 변경'),
                ),
              ),

              if (_message.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    _message,
                    style: TextStyle(color: Colors.blueGrey),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
