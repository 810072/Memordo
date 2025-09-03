// Frontend/lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

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
import 'providers/note_provider.dart';
import 'providers/scratchpad_provider.dart';

Future<void> main(List<String> args) async {
  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final arguments =
        args[2].isEmpty
            ? const <String, dynamic>{}
            : jsonDecode(args[2]) as Map<String, dynamic>;

    await dotenv.load(fileName: 'assets/.env');
    runApp(ChatbotPage(key: Key('chatbot_window_$windowId')));
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 1000),
      center: true,
      minimumSize: Size(800, 600),
      title: 'Memordo',
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setBackgroundColor(Colors.transparent);
      // ✨ [수정] 'setShadow' 메서드가 현재 window_manager 버전과 호환되지 않아 이 라인을 제거했습니다.
      // await windowManager.setShadow(true);
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
          ChangeNotifierProvider(create: (context) => NoteProvider()),
          ChangeNotifierProvider(create: (context) => ScratchpadProvider()),
        ],
        child: const MyApp(),
      ),
    );
  }
}

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
          initialRoute: '/main',
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

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activePage: _currentPage,
      onPageSelected: (pageType) {
        setState(() {
          _currentPage = pageType;
        });
      },
    );
  }
}
