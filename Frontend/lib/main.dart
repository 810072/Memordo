// lib/main.dart 파일에서 routes 부분을 아래와 같이 수정해주세요.
import 'package:flutter/material.dart';
import 'auth/login_page.dart';
import 'auth/signup_page.dart';
import 'auth/email_check_page.dart';
import 'auth/password_reset_page.dart';
import 'auth/find_id_page.dart';
// LeftSidebarLayout import는 그대로 둡니다. 다른 라우트에서 사용될 수 있으니까요.
import 'layout/left_sidebar_layout.dart';
import 'features/meeting_screen.dart'; // MeetingScreen import
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // 🔧 반드시 초기화
  await dotenv.load(fileName: 'assets/.env');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/login',
      routes: {
        '/login': (context) => LoginPage(),
        '/signup': (context) => SignUpPage(),
        // ✅ 여기서 LeftSidebarLayout wrapper를 제거합니다.
        // MeetingScreen 자체에서 레이아웃을 제공합니다.
        '/main': (context) => MeetingScreen(),
        '/emailCheck': (context) => EmailCheckPage(),
        '/findId': (context) => FindIdPage(),
        // '/passwordReset': 이메일 인자로 필요 → 별도 Navigator.push 사용
      },
    );
  }
}
