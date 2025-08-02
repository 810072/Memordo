// Frontend/lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart'; // ✨ window_manager 패키지 임포트

// 기존 임포트
import 'auth/login_page.dart';
import 'auth/signup_page.dart';
import 'auth/email_check_page.dart';
import 'auth/password_reset_page.dart';
import 'auth/find_id_page.dart';
import 'layout/ai_summary_controller.dart';
import 'layout/bottom_section_controller.dart';
import 'layout/main_layout.dart';
import 'features/page_type.dart';
import 'providers/file_system_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/token_status_provider.dart';
import 'features/chatbot_page.dart';

Future<void> main(List<String> args) async {
  // 새 창(챗봇)으로 실행될 경우의 로직
  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final arguments =
        args[2].isEmpty
            ? const <String, dynamic>{}
            : jsonDecode(args[2]) as Map<String, dynamic>;

    await dotenv.load(fileName: 'assets/.env');
    runApp(ChatbotPage(key: Key('chatbot_window_$windowId')));
  }
  // ✨ 기존 메인 앱 실행 로직 수정
  else {
    WidgetsFlutterBinding.ensureInitialized();
    // window_manager를 초기화합니다.
    await windowManager.ensureInitialized();

    // 창이 표시될 준비가 되면, 크기와 위치를 설정합니다.
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 1000), // 원하는 창의 너비와 높이
      center: true, // 창을 화면 중앙에 위치시킴
      minimumSize: Size(800, 600), // 창의 최소 크기 설정
      title: 'Memordo', // 창 제목 설정
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await dotenv.load(fileName: 'assets/.env');

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => AiSummaryController()),
          ChangeNotifierProvider(
            create: (context) => BottomSectionController(),
          ),
          ChangeNotifierProvider(create: (context) => FileSystemProvider()),
          ChangeNotifierProvider(create: (context) => ThemeProvider()),
          ChangeNotifierProvider(create: (context) => TokenStatusProvider()),
        ],
        child: const MyApp(),
      ),
    );
  }
}

// ============== 여기부터 아래 코드는 기존과 동일합니다 ==============

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Memordo',
          theme: themeProvider.currentThemeData,
          darkTheme: themeProvider.currentThemeData,
          themeMode:
              themeProvider.themeMode == AppThemeMode.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
          initialRoute: '/login',
          routes: {
            '/login': (context) => LoginPage(),
            '/signup': (context) => SignUpPage(),
            '/emailCheck': (context) => EmailCheckPage(),
            '/findId': (context) => const FindIdPage(),
            '/main': (context) => const MainLayoutWrapper(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/passwordReset') {
              final args = settings.arguments as String;
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

class MainLayoutWrapper extends StatefulWidget {
  const MainLayoutWrapper({super.key});

  @override
  State<MainLayoutWrapper> createState() => _MainLayoutWrapperState();
}

class _MainLayoutWrapperState extends State<MainLayoutWrapper> {
  PageType _currentPage = PageType.home;

  void _onPageSelected(PageType pageType) {
    setState(() {
      _currentPage = pageType;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activePage: _currentPage,
      onPageSelected: _onPageSelected,
    );
  }
}
