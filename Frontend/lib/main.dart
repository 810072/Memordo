// lib/main.dart
import 'package:flutter/material.dart';
import 'auth/login_page.dart';
import 'auth/signup_page.dart';
import 'auth/email_check_page.dart';
import 'auth/password_reset_page.dart'; // ✅ 임포트 추가
import 'auth/find_id_page.dart';
import 'features/meeting_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'layout/ai_summary_controller.dart'; // ✅ 이름 변경된 컨트롤러 임포트
import 'features/calendar_page.dart';
import 'features/graph_page.dart';
import 'features/history.dart';
import 'layout/bottom_section_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final _storage = FlutterSecureStorage();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AiSummaryController()),
        ChangeNotifierProvider(
          create: (context) => BottomSectionController(),
        ), // 👉 추가!
      ],
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
      theme: ThemeData(
        // ✅ 기본 테마 설정 (선택 사항)
        primaryColor: const Color(0xFF3d98f4),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1E293B),
          elevation: 1.0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => LoginPage(),
        '/signup': (context) => SignUpPage(),
        '/main': (context) => const MeetingScreen(), // ✅ MeetingScreen 사용
        '/calendar': (context) => const CalendarPage(), // ✅ CalendarPage 사용
        '/graph': (context) => const GraphPage(), // ✅ GraphPage 사용
        '/history': (context) => const HistoryPage(), // ✅ HistoryPage 사용
        '/emailCheck': (context) => EmailCheckPage(),
        '/findId': (context) => const FindIdPage(),
        // PasswordResetPage는 email을 받아야 하므로 routes보다는 MaterialPageRoute로 직접 호출하는 것이 일반적입니다.
        // '/passwordReset': (context) => PasswordResetPage(email: 'test@test.com'), // 예시
      },
    );
  }
}
