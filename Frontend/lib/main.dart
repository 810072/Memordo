import 'package:flutter/material.dart';
import 'auth/login_page.dart';
import 'auth/signup_page.dart';
import 'auth/email_check_page.dart';
import 'auth/password_reset_page.dart';
import 'auth/find_id_page.dart';
import 'layout/left_sidebar_layout.dart';
import 'features/meeting_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart'; // Provider 임포트
import 'layout/bottom_section_controller.dart'; // 새로 생성한 컨트롤러 임포트
import 'auth/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env');

  runApp(
    ChangeNotifierProvider(
      // MyApp을 ChangeNotifierProvider로 래핑
      create: (context) => BottomSectionController(), // 컨트롤러 인스턴스 생성
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const SplashPage(), // ✅ 자동 판단 페이지로 교체
      routes: {
        '/login': (context) => LoginPage(),
        '/signup': (context) => SignUpPage(),
        '/main': (context) => MeetingScreen(),
        '/emailCheck': (context) => EmailCheckPage(),
        '/findId': (context) => FindIdPage(),
      },
    );
  }
}
