// main.dart (기존 파일에 routes 부분에 추가)
import 'package:flutter/material.dart';
import 'meeting_screen.dart';
import 'left_sidebar_layout.dart';
import 'login_page.dart';
import 'signup_page.dart';
import 'email_check_page.dart';
import ' password_reset_page.dart';
import 'find_id_page.dart'; // ✅ 새로 추가된 파일 임포트

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/login',
      routes: {
        '/login': (context) => LoginPage(),
        '/signup': (context) => SignUpPage(),
        '/main':
            (context) => LeftSidebarLayout(
              activePage: PageType.home,
              child: MeetingScreen(),
            ),
        '/emailCheck': (context) => EmailCheckPage(),
        '/findId': (context) => FindIdPage(), // ✅ FindIdPage 라우트 추가
        // PasswordResetPage는 이메일 주소를 인자로 받으므로 named route보다는 MaterialPageRoute로 이동 시 전달하는 방식을 사용합니다.
      },
    ),
  );
}

// 이 앱은 main 함수에서 MaterialApp의 initialRoute를 사용하므로 이 MyApp 클래스는 사실상 사용되지 않습니다.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MeetingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
