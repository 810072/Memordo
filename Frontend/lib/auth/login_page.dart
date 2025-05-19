import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'email_check_page.dart';
import 'find_id_page.dart';

class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 이메일과 비밀번호 입력 필드 컨트롤러
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // 키보드 이벤트 처리를 위한 포커스 노드
  final FocusNode _focusNode = FocusNode();

  // 현재 눌린 키들을 추적하기 위한 Set
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  // 로그인 버튼 애니메이션 상태 (true일 경우 눌림 상태)
  bool _isButtonPressed = false;

  // API 서버 주소
  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  // 로그인 요청 함수
  Future<void> _login(BuildContext context) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // 이메일이나 비밀번호가 비어있을 경우 안내
    if (email.isEmpty || password.isEmpty) {
      print('이메일과 비밀번호를 입력해주세요.');
      return;
    }

    final url = Uri.parse('$baseUrl$apiPrefix/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      // 로그인 성공 시 메인 페이지로 이동
      if (response.statusCode == 200) {
        print('로그인 성공: ${response.body}');
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        print('로그인 실패: ${response.statusCode}, ${response.body}');
      }
    } catch (e) {
      print('로그인 오류: $e');
    }
  }

  // 애니메이션 효과와 함께 로그인 요청 실행
  Future<void> _triggerLoginWithAnimation() async {
    setState(() => _isButtonPressed = true); // 버튼을 눌린 상태로 설정

    await Future.delayed(Duration(milliseconds: 10)); // 짧은 눌림 효과
    await _login(context); // 로그인 요청 실행

    setState(() => _isButtonPressed = false); // 버튼 상태 복원
  }

  // 키 이벤트 핸들링 함수
  void _handleKey(RawKeyEvent event) {
    final key = event.logicalKey;

    if (event is RawKeyDownEvent) {
      // 이미 눌린 키는 무시
      if (_pressedKeys.contains(key)) return;

      _pressedKeys.add(key);

      // 엔터 키 입력 시 애니메이션 포함 로그인 실행
      if (key == LogicalKeyboardKey.enter) {
        _triggerLoginWithAnimation();
      }
    } else if (event is RawKeyUpEvent) {
      // 키가 떼어질 경우 Set에서 제거
      _pressedKeys.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RawKeyboardListener(
        focusNode: _focusNode,
        autofocus: true, // 화면 진입 시 자동 포커싱
        onKey: _handleKey, // 키 입력 처리 함수 지정
        child: Center(
          child: Container(
            width: 400,
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 이메일 입력 필드
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

                // 비밀번호 입력 필드
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Password'),
                ),
                SizedBox(height: 32),

                // 로그인 버튼 (눌림 애니메이션 반영)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 100),
                    curve: Curves.easeInOut,
                    transform:
                        _isButtonPressed
                            ? Matrix4.translationValues(0, 2, 0)
                            : Matrix4.identity(),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        elevation:
                            _isButtonPressed ? 2 : 6, // 눌렸을 때 낮은 elevation
                        padding:
                            _isButtonPressed
                                ? EdgeInsets.symmetric(vertical: 10)
                                : EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => _login(context),
                      child: Text(
                        'LOGIN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              _isButtonPressed
                                  ? FontWeight.w600
                                  : FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 24),

                // 회원가입 링크
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

                // 아이디/비밀번호 찾기 링크
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
                      child: Text(
                        "아이디 찾기",
                        style: TextStyle(color: Colors.blue),
                      ),
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
      ),
    );
  }
}
