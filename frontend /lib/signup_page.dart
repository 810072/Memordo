import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // HTTP 통신을 위한 라이브러리 임포트
import 'dart:convert'; // JSON 처리를 위한 라이브러리 임포트

// 회원가입 페이지 위젯
class SignUpPage extends StatefulWidget {
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

// SignUpPage 위젯의 상태를 관리하는 클래스
class _SignUpPageState extends State<SignUpPage> {
  // 텍스트 입력 필드를 제어하는 컨트롤러들
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  // 사용자에게 표시할 메시지
  String _message = '';
  // 로딩 상태 (회원가입 버튼 활성화/비활성화 및 로딩 인디케이터 표시용)
  bool _isLoading = false;
  // 이메일 인증 완료 여부
  bool _emailVerified = false;

  // API 호출 형식을 '/memo/api'로 변경하기 위한 기본 URL 및 접두사
  final String baseUrl = 'https://aidoctorgreen.com'; // API 서버의 기본 URL
  final String apiPrefix = '/memo/api'; // API 경로 접두사

  // 이메일 인증 코드를 발송하는 비동기 함수
  Future<void> _sendVerificationCode() async {
    final email = _emailController.text.trim(); // 이메일 입력 필드의 텍스트 가져오기 (공백 제거)
    if (email.isEmpty) {
      setState(() => _message = '이메일을 입력해주세요.'); // 이메일이 비어있으면 메시지 설정
      return; // 함수 종료
    }

    // API 호출 경로 변경: baseUrl + apiPrefix + 엔드포인트
    final url = Uri.parse('$baseUrl$apiPrefix/m/send-verification');

    try {
      // HTTP POST 요청 보내기
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'}, // 요청 헤더 설정 (JSON 형식)
        body: jsonEncode({'email': email}), // 요청 본문 (JSON 형식)
      );

      // 응답 본문을 JSON으로 디코딩
      final data = jsonDecode(response.body);
      // 응답 데이터에서 메시지를 가져와 상태 업데이트
      setState(() => _message = data['message'] ?? '전송 실패');
    } catch (e) {
      // 오류 발생 시 상태 업데이트
      setState(() => _message = '전송 오류: $e');
    }
  }

  // 이메일 인증 코드를 확인하는 비동기 함수
  Future<void> _verifyCode() async {
    final email = _emailController.text.trim(); // 이메일 가져오기
    final code = _codeController.text.trim(); // 인증 코드 가져오기

    // API 호출 경로 변경: baseUrl + apiPrefix + 엔드포인트
    final url = Uri.parse('$baseUrl$apiPrefix/m/verify-code');

    try {
      // HTTP POST 요청 보내기
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'}, // 요청 헤더 설정
        body: jsonEncode({'email': email, 'code': code}), // 요청 본문
      );

      // 응답 본문을 JSON으로 디코딩
      final data = jsonDecode(response.body);

      // 응답 상태 코드 확인
      if (response.statusCode == 200) {
        // 성공 시
        setState(() {
          _message = '인증 성공'; // 메시지 설정
          _emailVerified = true; // 이메일 인증 완료 상태 설정
        });
      } else {
        // 실패 시
        setState(() {
          _message = data['message'] ?? '인증 실패'; // 실패 메시지 설정
        });
      }
    } catch (e) {
      // 오류 발생 시 상태 업데이트
      setState(() => _message = '인증 오류: $e');
    }
  }

  // 회원가입을 처리하는 비동기 함수
  Future<void> _signUp() async {
    final email = _emailController.text.trim(); // 이메일 가져오기
    final password = _passwordController.text.trim(); // 비밀번호 가져오기

    // 이메일 인증이 완료되지 않았으면 회원가입 진행 안 함
    if (!_emailVerified) {
      setState(() => _message = "이메일 인증을 먼저 완료해주세요.");
      return;
    }

    // 이메일 또는 비밀번호가 비어있으면 메시지 설정
    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = "이메일과 비밀번호를 입력해주세요.");
      return;
    }

    // 로딩 상태 시작 및 메시지 초기화
    setState(() {
      _isLoading = true;
      _message = '';
    });

    // API 호출 경로 변경: baseUrl + apiPrefix + 엔드포인트
    final url = Uri.parse('$baseUrl$apiPrefix/signup');

    try {
      // HTTP POST 요청 보내기 (회원가입)
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'}, // 요청 헤더 설정
        body: jsonEncode({
          'email': email,
          'password': password,
        }), // 요청 본문 (이메일, 비밀번호)
      );

      // 응답 본문을 JSON으로 디코딩
      final res = jsonDecode(response.body);

      // 응답 상태 코드 확인
      if (response.statusCode == 201) {
        // 성공 (Created) 시
        setState(() => _message = "회원가입 성공!"); // 성공 메시지 설정
        Navigator.pop(context); // 현재 페이지 (회원가입 페이지) 닫고 이전 페이지로 이동
      } else {
        // 실패 시
        setState(() => _message = res['message'] ?? '회원가입 실패'); // 실패 메시지 설정
      }
    } catch (e) {
      // 오류 발생 시 상태 업데이트
      setState(() => _message = '회원가입 오류: ${e.toString()}');
    } finally {
      // 작업 완료 후 로딩 상태 해제
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 공통 텍스트 스타일 정의
    final textStyle = TextStyle(fontSize: 16);

    return Scaffold(
      // 기본적인 앱 화면 구조 제공
      body: Stack(
        // 여러 위젯을 겹쳐 표시
        children: [
          // 뒤로가기 버튼 (상단 좌측)
          Positioned(
            top: 32,
            left: 16,
            child: IconButton(
              icon: Icon(Icons.arrow_back), // 뒤로가기 아이콘
              onPressed: () => Navigator.pop(context), // 버튼 클릭 시 현재 페이지 닫기
            ),
          ),
          // 회원가입 폼 (중앙)
          Center(
            // 화면 중앙에 배치
            child: Container(
              // 콘텐츠 영역 제한 및 패딩 적용
              width: 400, // 너비
              padding: EdgeInsets.all(24), // 내부 여백
              child: Column(
                // 자식 위젯을 세로로 배치
                mainAxisSize: MainAxisSize.min, // 컬럼 크기를 자식 위젯에 맞춤
                children: [
                  SizedBox(height: 32), // 상단 여백
                  // 이메일 입력 필드
                  TextField(
                    controller: _emailController, // 컨트롤러 연결
                    decoration: InputDecoration(
                      labelText: '이메일', // 레이블 텍스트
                      labelStyle: textStyle, // 레이블 스타일
                    ),
                  ),
                  SizedBox(height: 16), // 위젯 간 세로 간격
                  // 인증 코드 발송 버튼
                  ElevatedButton(
                    onPressed:
                        _sendVerificationCode, // 버튼 클릭 시 _sendVerificationCode 함수 호출
                    child: Text('인증 코드 발송'), // 버튼 텍스트
                  ),
                  SizedBox(height: 16), // 위젯 간 세로 간격
                  // 인증 코드 입력 필드
                  TextField(
                    controller: _codeController, // 컨트롤러 연결
                    decoration: InputDecoration(
                      labelText: '인증 코드', // 레이블 텍스트
                      labelStyle: textStyle, // 레이블 스타일
                    ),
                  ),
                  SizedBox(height: 16), // 위젯 간 세로 간격
                  // 인증 코드 확인 버튼
                  ElevatedButton(
                    onPressed: _verifyCode, // 버튼 클릭 시 _verifyCode 함수 호출
                    child: Text('인증 코드 확인'), // 버튼 텍스트
                  ),
                  Divider(height: 32), // 구분선 및 세로 간격
                  // 비밀번호 입력 필드
                  TextField(
                    controller: _passwordController, // 컨트롤러 연결
                    obscureText: true, // 텍스트 숨김
                    decoration: InputDecoration(
                      labelText: '비밀번호', // 레이블 텍스트
                      labelStyle: textStyle, // 레이블 스타일
                    ),
                  ),
                  SizedBox(height: 24), // 위젯 간 세로 간격
                  // 회원가입 버튼
                  SizedBox(
                    width: double.infinity, // 부모 너비 전체 사용
                    height: 48, // 높이
                    child: ElevatedButton(
                      // 로딩 중이 아닐 때만 버튼 활성화
                      onPressed: _isLoading ? null : _signUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple, // 배경색
                      ),
                      // 로딩 중이면 CircularProgressIndicator, 아니면 '회원가입' 텍스트 표시
                      child:
                          _isLoading
                              ? CircularProgressIndicator(color: Colors.white)
                              : Text('회원가입'),
                    ),
                  ),
                  // 상태 메시지 표시 영역 (메시지가 비어있지 않을 때만 표시)
                  if (_message.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 16), // 상단 여백
                      child: Text(
                        _message, // 메시지 텍스트
                        style: TextStyle(
                          // 이메일 인증 완료 여부에 따라 텍스트 색상 변경
                          color: _emailVerified ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
