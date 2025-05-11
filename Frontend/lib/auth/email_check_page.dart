// email_check_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'password_reset_page.dart';

// 이메일 확인 페이지 위젯 (StatefulWidget으로 변경)
class EmailCheckPage extends StatefulWidget {
  @override
  _EmailCheckPageState createState() => _EmailCheckPageState();
}

class _EmailCheckPageState extends State<EmailCheckPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false; // 로딩 상태를 관리하는 변수

  // API 기본 URL
  final String baseUrl = 'https://aidoctorgreen.com'; // 실제 서버 주소
  // API 경로 접두사
  final String apiPrefix = '/memo/api';

  // 이메일을 이용해 ID를 찾는 API 호출 함수
  Future<void> _findIdByEmail() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      // 이메일이 비어있을 때 사용자에게 알림
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('이메일 주소를 입력해주세요.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // 로딩 상태 시작
    setState(() {
      _isLoading = true;
    });

    // API 호출 경로: baseUrl + apiPrefix + find-id 엔드포인트
    final url = Uri.parse('$baseUrl$apiPrefix/check-email');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}), // 이메일을 요청 본문으로 전송
      );

      // 응답 상태 코드 확인
      if (response.statusCode == 200) {
        // ✅ API 호출 성공 (HTTP 상태 코드 200)
        try {
          final responseBody = jsonDecode(response.body);
          print('아이디 찾기 API 응답 (200): ${response.body}');

          // ✅ 응답 본문에서 'isDuplicate' 값을 확인
          if (responseBody.containsKey('isDuplicate') &&
              responseBody['isDuplicate'] is bool) {
            bool isDuplicate = responseBody['isDuplicate'];

            if (isDuplicate) {
              // isDuplicate가 true일 때: 계정 발견, 다음 페이지로 이동
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('해당 이메일로 등록된 계정을 찾았습니다.'),
                  backgroundColor: Colors.green,
                ),
              );
              print('아이디 찾기 성공: 계정 발견');

              // 비밀번호 재설정 페이지로 이동
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          PasswordResetPage(email: email), // 입력된 이메일 주소 전달
                ),
              );
            } else {
              // isDuplicate가 false일 때: 계정 없음
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('해당 이메일로 등록된 계정을 찾을 수 없습니다.'),
                  backgroundColor: Colors.orangeAccent,
                ),
              );
              print('아이디 찾기 성공: 계정 없음 (isDuplicate: false)');
            }
          } else {
            // 'isDuplicate' 키가 없거나 bool 값이 아닐 경우
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('알 수 없는 API 응답 형식입니다.'),
                backgroundColor: Colors.orangeAccent,
              ),
            );
            print('아이디 찾기 성공 - 알 수 없는 응답 형식: ${response.body}');
          }
        } catch (e) {
          // JSON 파싱 오류
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('API 응답 파싱 오류: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
          print('아이디 찾기 성공 - JSON 파싱 오류: $e');
        }
      } else {
        // API 호출 실패 (HTTP 상태 코드 200 이외)
        print('아이디 찾기 API 응답 (${response.statusCode}): ${response.body}');
        try {
          final errorBody = jsonDecode(response.body);
          final errorMessage =
              errorBody['message'] ??
              '아이디 찾기에 실패했습니다 (상태 코드: ${response.statusCode}).';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('오류: $errorMessage'),
              backgroundColor: Colors.redAccent,
            ),
          );
          print('아이디 찾기 실패: ${response.statusCode}, ${response.body}');
        } catch (e) {
          // 응답 본문이 JSON이 아니거나 파싱 오류
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('API 오류 발생 (상태 코드: ${response.statusCode})'),
              backgroundColor: Colors.redAccent,
            ),
          );
          print('아이디 찾기 실패 - 응답 처리 오류: ${response.statusCode}, $e');
        }
      }
    } catch (e) {
      // 네트워크 오류 등 예외 발생
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('네트워크 오류 발생: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      print('네트워크 오류 발생: $e');
    } finally {
      // 로딩 상태 종료
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    // 위젯이 dispose될 때 컨트롤러도 정리
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('비밀번호 찾기'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Center(
        child: SingleChildScrollView(
          // 내용이 많아지면 스크롤 가능하도록 SingleChildScrollView 추가
          padding: EdgeInsets.all(24),
          child: Container(
            width: 400, // 최대 너비 지정
            constraints: BoxConstraints(maxWidth: 400), // 반응형으로 최대 너비 제한
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, // 가로로 확장
              children: [
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: '이메일 주소 입력',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    // 로딩 중일 때는 버튼 비활성화
                    onPressed: _isLoading ? null : _findIdByEmail,
                    child:
                        _isLoading
                            ? SizedBox(
                              // 로딩 중일 때 로딩 인디케이터 표시
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : Text('이메일 등록'), // 버튼 텍스트
                  ),
                ),
                // ✅ _resultMessage를 직접 표시하는 대신 SnackBar 사용
                // if (_resultMessage.isNotEmpty)
                //   Padding(
                //     padding: const EdgeInsets.only(top: 16.0),
                //     child: Text(
                //       _resultMessage,
                //       style: TextStyle(
                //         color: _resultMessage.startsWith('오류') || _resultMessage.startsWith('네트워크')
                //             ? Colors.red
                //             : Colors.black87,
                //       ),
                //       textAlign: TextAlign.center,
                //     ),
                //   ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
