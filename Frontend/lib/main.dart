import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
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

// macOS에서만 사용할 백엔드 서버 프로세스 변수
Process? _macOSBackendProcess;

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

    // ✨ [수정] 앱 시작 로직을 main 함수에서 분리하여 관리합니다.
    await _startBackendServer();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 1000),
      center: true,
      minimumSize: Size(800, 600),
      title: 'Memordo',
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setBackgroundColor(Colors.transparent);
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

/// OS에 따라 적절한 방법으로 백엔드 서버를 시작하는 함수
Future<void> _startBackendServer() async {
  if (!kReleaseMode) {
    debugPrint('개발 모드에서는 백엔드 서버를 자동으로 실행하지 않습니다.');
    return;
  }
  try {
    if (Platform.isMacOS) {
      String backendName = 'memordo_ai_backend';
      String resourcesPath = p.join(
        p.dirname(Platform.resolvedExecutable),
        '..',
        'Resources',
        backendName,
      );

      File backendFile = File(resourcesPath);
      if (await backendFile.exists()) {
        debugPrint('macOS 백엔드 서버를 시작합니다: $resourcesPath');
        // ✨ [수정] 'detached: true'를 'mode: ProcessStartMode.detached'로 변경
        _macOSBackendProcess = await Process.start(
          resourcesPath,
          [],
          mode: ProcessStartMode.detached,
        );
        debugPrint('macOS 백엔드 서버 프로세스 시작됨 (PID: ${_macOSBackendProcess?.pid})');
      } else {
        debugPrint('오류: macOS 백엔드 서버 실행 파일을 찾을 수 없습니다.');
      }
    } else if (Platform.isWindows) {
      debugPrint('Windows에서는 네이티브 코드가 백엔드 서버를 시작합니다.');
    }
  } catch (e) {
    debugPrint('백엔드 서버 시작 중 오류 발생: $e');
  }
}

/// OS에 따라 적절한 방법으로 백엔드 서버를 종료하는 함수
Future<void> _stopBackendServer() async {
  if (Platform.isMacOS) {
    if (_macOSBackendProcess != null) {
      debugPrint('macOS 백엔드 서버(PID: ${_macOSBackendProcess?.pid})를 종료합니다.');
      _macOSBackendProcess!.kill();
      _macOSBackendProcess = null;
    }
  } else if (Platform.isWindows) {
    debugPrint('Windows에서는 네이티브 코드가 백엔드 서버를 종료합니다.');
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

// ✨ [수정] WindowListener를 mixin하여 창 닫기 이벤트를 감지합니다.
class MainLayoutWrapper extends StatefulWidget {
  const MainLayoutWrapper({super.key});

  @override
  State<MainLayoutWrapper> createState() => _MainLayoutWrapperState();
}

class _MainLayoutWrapperState extends State<MainLayoutWrapper>
    with WindowListener {
  PageType _currentPage = PageType.home;
  String? _initialTextForMemo;

  @override
  void initState() {
    super.initState();
    // 창 이벤트 리스너를 등록합니다.
    windowManager.addListener(this);
    _configureWindowCloseHandler();

    Provider.of<NoteProvider>(context, listen: false).onNewMemoFromHistory = (
      text,
    ) {
      if (!mounted) return;
      setState(() {
        _initialTextForMemo = text;
        _currentPage = PageType.home;
      });
    };
  }

  // 비동기 작업을 위해 별도 함수로 분리
  void _configureWindowCloseHandler() async {
    await windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    // 위젯이 소멸될 때 리스너를 제거합니다.
    windowManager.removeListener(this);
    super.dispose();
  }

  /// ✨ [추가] 창을 닫으려고 할 때 호출되는 콜백 메서드
  @override
  Future<void> onWindowClose() async {
    // 사용자에게 종료 여부를 확인하는 대화상자를 띄웁니다.
    bool isConfirmed =
        await showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('앱을 종료하시겠습니까?'),
              content: const Text('변경사항이 저장되지 않을 수 있습니다.'),
              actions: [
                TextButton(
                  child: const Text('취소'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: const Text('종료'),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        ) ??
        false;

    if (isConfirmed) {
      await _stopBackendServer(); // 백엔드 서버를 종료하고
      await windowManager.destroy(); // 실제 창을 닫습니다.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activePage: _currentPage,
      initialTextForMemo: _initialTextForMemo,
      onPageSelected: (pageType) {
        setState(() {
          if (_currentPage == PageType.home && pageType != PageType.home) {
            _initialTextForMemo = null;
          }
          _currentPage = pageType;
        });
      },
    );
  }
}
