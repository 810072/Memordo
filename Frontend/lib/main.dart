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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'services/AI_run.dart'; // AI 백엔드 프로세스 실행/종료 연동
import 'layout/main_layout.dart'; // MainLayout 임포트
import 'features/page_type.dart'; // PageType 임포트
import 'providers/file_system_provider.dart'; // FileSystemProvider 임포트
import 'providers/theme_provider.dart'; // ThemeProvider 추가
import 'providers/token_status_provider.dart'; // ✨ 추가: TokenStatusProvider 임포트

final _storage = FlutterSecureStorage();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env');

  // 백엔드 서비스를 자동으로 시작하려면 주석 해제
  // await BackendService.startPythonBackend();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AiSummaryController()),
        ChangeNotifierProvider(create: (context) => BottomSectionController()),
        // 여기에 FileSystemProvider를 추가합니다.
        ChangeNotifierProvider(create: (context) => FileSystemProvider()),
        ChangeNotifierProvider(
          create: (context) => ThemeProvider(),
        ), // ThemeProvider 추가
        ChangeNotifierProvider(
          create: (context) => TokenStatusProvider(),
        ), // ✨ 추가: TokenStatusProvider 등록
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 앱 종료 시 Python 서버 자동 종료
    BackendService.stopPythonBackend();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 완전히 종료될 때 확실히 백엔드도 종료
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      BackendService.stopPythonBackend();
    }
    super.didChangeAppLifecycleState(state);
  }

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
