// find_id_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// 아이디 찾기 페이지 위젯 (StatefulWidget으로 변경)
class FindIdPage extends StatefulWidget {
  const FindIdPage({super.key});

  @override
  _FindIdPageState createState() => _FindIdPageState();
}

// FindIdPage 위젯의 상태를 관리하는 클래스
class _FindIdPageState extends State<FindIdPage> {
  // 이메일 입력 필드를 제어할 컨트롤러
  final TextEditingController _emailController = TextEditingController();

  // ✅ 아이디 찾기 결과를 저장할 상태 변수
  String _resultMessage = '';
  // 로딩 상태 표시를 위한 변수
  bool _isLoading = false;

  // API 기본 URL (실제 서버 주소로 변경 필요)
  final String baseUrl = 'https://aidoctorgreen.com'; // 예시 URL
  // API 경로 접두사
  final String apiPrefix = '/memo/api';

  // 아이디 찾기 API 호출 함수
  Future<void> _findId(BuildContext context) async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _resultMessage = '이메일 주소를 입력해주세요.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = ''; // 새로운 검색 시작 시 이전 메시지 초기화
    });

    // TODO: 백엔드 API 명세를 확인하여 실제 아이디 찾기 엔드포인트를 사용해야 합니다.
    // 제공해주신 응답 {"isDuplicate":true}를 바탕으로, 이 엔드포인트가 이메일 존재 여부를 확인하는 것으로 가정합니다.
    final url = Uri.parse(
      '$baseUrl$apiPrefix/check-email',
    ); // API 호출 경로 예시 (실제 백엔드 경로로 변경)

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}), // 이메일을 요청 본문으로 전송
      );

      if (response.statusCode == 200) {
        // ✅ API 호출 성공 (HTTP 상태 코드 200)
        try {
          final responseBody = jsonDecode(response.body);
          // ✅ 응답 본문에서 'isDuplicate' 값을 확인하여 결과 메시지 설정
          if (responseBody.containsKey('isDuplicate') &&
              responseBody['isDuplicate'] is bool) {
            bool isDuplicate = responseBody['isDuplicate'];
            setState(() {
              if (isDuplicate) {
                _resultMessage =
                    '해당 이메일로 등록된 계정이 있습니다.'; // isDuplicate가 true일 때 메시지
                // TODO: 여기서 실제 아이디를 사용자에게 어떻게 전달할지 (예: 이메일로 보내기) 추가 로직 필요
              } else {
                _resultMessage =
                    '해당 이메일로 등록된 계정을 찾을 수 없습니다.'; // isDuplicate가 false일 때 메시지
              }
            });
            print('아이디 찾기 성공 (응답 파싱): ${response.body}');
          } else {
            // 'isDuplicate' 키가 없거나 bool 값이 아닐 경우
            setState(() {
              _resultMessage = '알 수 없는 API 응답 형식입니다.';
            });
            print('아이디 찾기 성공 - 알 수 없는 응답 형식: ${response.body}');
          }
        } catch (e) {
          // JSON 파싱 오류
          setState(() {
            _resultMessage = 'API 응답 파싱 오류: $e';
          });
          print('아이디 찾기 성공 - JSON 파싱 오류: $e');
        }
      } else {
        // API 호출 실패 (HTTP 상태 코드 200 이외)
        // TODO: 응답 본문 파싱 및 사용자에게 실패 이유 알림
        try {
          final errorBody = jsonDecode(response.body);
          final errorMessage =
              errorBody['message'] ??
              '아이디 찾기에 실패했습니다 (상태 코드: ${response.statusCode}).';
          setState(() {
            _resultMessage = '오류: $errorMessage';
          });
          print('아이디 찾기 실패: ${response.statusCode}, ${response.body}');
        } catch (e) {
          // 응답 본문이 JSON이 아니거나 파싱 오류
          setState(() {
            _resultMessage = 'API 오류 발생 (상태 코드: ${response.statusCode})';
          });
          print('아이디 찾기 실패 - 응답 처리 오류: ${response.statusCode}, $e');
        }
      }
    } catch (e) {
      // 네트워크 오류 등 예외 발생
      setState(() {
        _resultMessage = '네트워크 오류 발생: $e';
      });
      print('아이디 찾기 오류: $e');
    } finally {
      // 로딩 상태 종료
      setState(() {
        _isLoading = false;
      });
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
      appBar: AppBar(title: Text('아이디 찾기'), backgroundColor: Colors.deepPurple),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Container(
            width: 400,
            constraints: BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ✅ 결과 메시지 표시 텍스트 위젯
                if (_resultMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text(
                      _resultMessage,
                      style: TextStyle(
                        fontSize: 16,
                        // 메시지 내용에 따라 색상 변경: '오류' 포함 시 빨간색, 계정 존재 시 녹색, 계정 없음 시 파란색 (예시)
                        color:
                            _resultMessage.startsWith('오류')
                                ? Colors.red
                                : (_resultMessage.contains('등록된 계정이 있습니다')
                                    ? Colors.green
                                    : Colors.blue),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // 등록된 이메일 입력 필드
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: '등록된 이메일 주소',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isLoading, // 로딩 중일 때 입력 비활성화
                ),
                SizedBox(height: 24),

                // 아이디 찾기 버튼
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isLoading ? null : () => _findId(context),
                    child:
                        _isLoading
                            ? CircularProgressIndicator(color: Colors.white)
                            : Text('아이디 찾기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
