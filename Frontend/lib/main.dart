// lib/main.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

import 'auth/auth_dialog.dart'; // ✨ [수정] 페이지들 대신 AuthDialog 임포트
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
import 'providers/tab_provider.dart';
import 'viewmodels/history_viewmodel.dart';
import 'viewmodels/calendar_viewmodel.dart';
import 'viewmodels/graph_viewmodel.dart';
import 'providers/status_bar_provider.dart';
import 'viewmodels/calendar_sidebar_viewmodel.dart';

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
          ChangeNotifierProvider(create: (context) => TabProvider()),
          ChangeNotifierProvider(create: (context) => HistoryViewModel()),
          ChangeNotifierProvider(create: (context) => CalendarViewModel()),
          ChangeNotifierProvider(create: (context) => GraphViewModel()),
          ChangeNotifierProvider(create: (context) => StatusBarProvider()),
          ChangeNotifierProvider(
            create: (context) => CalendarSidebarViewModel(),
          ),
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
            // ✨ [수정] 메인 화면 경로만 남깁니다.
            '/main': (context) => const MainLayoutWrapper(),
          },
          // ✨ [삭제] onGenerateRoute는 더 이상 필요 없습니다.
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

class _MainLayoutWrapperState extends State<MainLayoutWrapper>
    with WindowListener {
  String? _initialTextForMemo;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _configureWindowCloseHandler();
    _setupMethodHandler();

    Provider.of<NoteProvider>(context, listen: false).onNewMemoFromHistory = (
      text,
    ) {
      if (!mounted) return;
      setState(() {
        _initialTextForMemo = text;
      });
    };
  }

  void _configureWindowCloseHandler() async {
    await windowManager.setPreventClose(true);
  }

  void _setupMethodHandler() {
    DesktopMultiWindow.setMethodHandler((
      MethodCall call,
      int fromWindowId,
    ) async {
      if (call.method == 'open_document') {
        final String relativePath = call.arguments as String;
        if (!mounted) return;

        try {
          final fsProvider = Provider.of<FileSystemProvider>(
            context,
            listen: false,
          );
          final rootPath = await fsProvider.getOrCreateNoteFolderPath();
          final fullPath = p.join(rootPath, relativePath);

          final tabProvider = Provider.of<TabProvider>(context, listen: false);
          final file = File(fullPath);

          if (await file.exists()) {
            final content = await file.readAsString();
            tabProvider.openNewTab(filePath: fullPath, content: content);
          } else {
            throw Exception('File not found at path: $fullPath');
          }
        } catch (e) {
          debugPrint('Error handling open_document call: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    Provider.of<NoteProvider>(context, listen: false).onNewMemoFromHistory =
        null;
    DesktopMultiWindow.setMethodHandler(null);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
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
      await _stopBackendServer();
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      initialTextForMemo: _initialTextForMemo,
      onPageSelected: (pageType) {
        setState(() {
          if (pageType != PageType.home) {
            _initialTextForMemo = null;
          }
        });
      },
    );
  }
}
