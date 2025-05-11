import 'package:flutter/material.dart';
import 'auth/login_page.dart';
import 'auth/signup_page.dart';
import 'auth/email_check_page.dart';
import 'auth/password_reset_page.dart';
import 'auth/find_id_page.dart';
import 'layout/left_sidebar_layout.dart';
import 'features/meeting_screen.dart';
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
