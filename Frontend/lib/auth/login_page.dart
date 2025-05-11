// login_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'email_check_page.dart';
import 'find_id_page.dart';

// 로그인 페이지 위젯
class LoginPage extends StatelessWidget {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // API 기본 URL (실제 서버 주소로 변경 필요)
  final String baseUrl = 'https://aidoctorgreen.com'; // 예시 URL
  // ✅ API 경로 접두사 추가
  final String apiPrefix = '/memo/api';

  // 로그인 API 호출 함수
  Future<void> _login(BuildContext context) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      // TODO: 이메일 또는 비밀번호가 비어있을 때 사용자에게 알림 (예: SnackBar)
      print('이메일과 비밀번호를 입력해주세요.');
      return;
    }

    // ✅ API 호출 경로 변경: baseUrl + apiPrefix + 엔드포인트
    final url = Uri.parse('$baseUrl$apiPrefix/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        // ✅ 로그인 성공
        // TODO: 응답 본문 파싱 (LoginResponse 모델 참고)
        // final loginResponse = jsonDecode(response.body);
        print('로그인 성공: ${response.body}');

        // 메인 페이지로 이동 (현재 페이지 교체)
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        // 로그인 실패
        // TODO: 응답 본문 파싱 및 사용자에게 실패 이유 알림
        print('로그인 실패: ${response.statusCode}, ${response.body}');
        // 예: showDialog 또는 SnackBar로 실패 메시지 표시
      }
    } catch (e) {
      // 네트워크 오류 등 예외 발생
      print('로그인 오류: $e');
      // TODO: 사용자에게 오류 발생 알림
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
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
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  onPressed: () => _login(context),
                  child: Text('LOGIN'),
                ),
              ),
              SizedBox(height: 24),
              InkWell(
                onTap: () {
                  Navigator.pushNamed(context, '/signup');
                },
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
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => FindIdPage()),
                      );
                    },
                    child: Text("아이디 찾기", style: TextStyle(color: Colors.blue)),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EmailCheckPage(),
                        ),
                      );
                    },
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
    );
  }
}
