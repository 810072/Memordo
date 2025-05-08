import 'package:flutter/material.dart';
import 'meeting_screen.dart';
import 'left_sidebar_layout.dart';
import 'login_page.dart';
import 'signup_page.dart';
import 'email_check_page.dart';
import 'password_reset_page.dart';
import 'find_id_page.dart';
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
        '/main':
            (context) => LeftSidebarLayout(
              activePage: PageType.home,
              child: MeetingScreen(),
            ),
        '/emailCheck': (context) => EmailCheckPage(),
        '/findId': (context) => FindIdPage(),
        // '/passwordReset': 이메일 인자로 필요 → 별도 Navigator.push 사용
      },
    );
  }
}
