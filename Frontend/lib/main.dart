// Frontend/lib/main.dart
import 'package:flutter/material.dart';
import 'auth/login_page.dart';
import 'auth/signup_page.dart';
import 'auth/email_check_page.dart';
import 'auth/password_reset_page.dart';
import 'auth/find_id_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'layout/ai_summary_controller.dart';
import 'layout/bottom_section_controller.dart';
// import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // 이 파일에서 직접 사용되지 않음

// import 'services/AI_run.dart'; // AI 백엔드 자동 실행/종료 로직 제거
import 'layout/main_layout.dart';
import 'features/page_type.dart';
import 'providers/file_system_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/token_status_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env');

  // Python 백엔드 자동 실행 로직이 제거되었습니다.
  // await BackendService.startPythonBackend();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AiSummaryController()),
        ChangeNotifierProvider(create: (context) => BottomSectionController()),
        ChangeNotifierProvider(create: (context) => FileSystemProvider()),
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => TokenStatusProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

// MyApp을 StatelessWidget으로 변경하여 백엔드 프로세스 관리 로직을 완전히 제거했습니다.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Consumer를 사용하여 ThemeProvider의 변화를 구독하고 MaterialApp을 다시 빌드합니다.
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Memordo', // 앱 제목 추가
          theme: themeProvider.currentThemeData, // Light 테마 설정
          darkTheme:
              themeProvider.currentThemeData, // Dark 테마 설정 (동일한 ThemeData 사용)
          themeMode:
              themeProvider.themeMode == AppThemeMode.dark
                  ? ThemeMode.dark
                  : ThemeMode.light, // 테마 모드 설정

          initialRoute: '/login', // 앱 시작 시 로그인 페이지로 이동
          routes: {
            '/login': (context) => LoginPage(),
            '/signup': (context) => SignUpPage(),
            '/emailCheck': (context) => EmailCheckPage(),
            '/findId': (context) => const FindIdPage(),
            '/main':
                (context) =>
                    const MainLayoutWrapper(), // MainLayout을 래핑하여 초기 페이지 설정
          },
          onGenerateRoute: (settings) {
            // PasswordResetPage와 같이 인자가 필요한 라우트는 onGenerateRoute를 사용
            if (settings.name == '/passwordReset') {
              final args = settings.arguments as String; // 이메일 인자를 받음
              return MaterialPageRoute(
                builder: (context) => PasswordResetPage(email: args),
              );
            }
            return null;
          },
        );
      },
    );
  }
}

// MainLayout을 래핑하여 초기 PageType을 설정하는 위젯
class MainLayoutWrapper extends StatefulWidget {
  const MainLayoutWrapper({super.key});

  @override
  State<MainLayoutWrapper> createState() => _MainLayoutWrapperState();
}

class _MainLayoutWrapperState extends State<MainLayoutWrapper> {
  PageType _currentPage = PageType.home; // 초기 페이지를 'home'(MeetingScreen)으로 설정

  void _onPageSelected(PageType pageType) {
    setState(() {
      _currentPage = pageType;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activePage: _currentPage,
      onPageSelected: _onPageSelected, // MainLayout에 콜백 전달
    );
  }
}
