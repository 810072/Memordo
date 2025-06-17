import 'dart:io';
import 'dart:convert'; // utf8 디코딩을 위해 필요

/// 백엔드(Python 서버) 프로세스 관리를 위한 서비스 클래스
class BackendService {
  // Python 백엔드 프로세스를 저장할 변수 (앱 종료 시 같이 종료하려면 static)
  static Process? _pythonBackendProcess;

  /// Python 백엔드 실행 함수
  /// 앱 시작 시 호출 (이미 실행 중이면 재실행하지 않음)
  static Future<void> startPythonBackend() async {
    // 이미 실행 중이면 중복 실행 방지
    if (_pythonBackendProcess != null) {
      print('Python Backend is already running.');
      return;
    }

    // 데스크탑 환경에서만 지원 (Windows, Mac, Linux)
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      print(
        'Python backend can only be started on desktop platforms (Windows, macOS, Linux).',
      );
      return;
    }

    // 운영체제별 python 명령어 결정
    String pythonCmd = Platform.isWindows ? 'python' : 'python3';

    // Python 서버(app.py) 상대 경로 (Flutter 실행 위치 기준, 상황에 따라 경로 조정 필요)
    String scriptPath = '../py/app.py';

    print('Attempting to start Python backend: $pythonCmd $scriptPath');

    try {
      // 파이썬 서버(app.py) 실행
      _pythonBackendProcess = await Process.start(
        pythonCmd,
        [scriptPath],
        runInShell: true, // Windows, Mac, Linux 모두 안전하게 실행
      );

      print('Python Backend Started (PID: ${_pythonBackendProcess!.pid})');

      // Python 서버의 표준 출력(로그) Flutter 콘솔에 출력 (디버깅/모니터링용)
      _pythonBackendProcess!.stdout
          .transform(utf8.decoder)
          .listen(
            (data) {
              print('Python STDOUT: $data');
            },
            onError: (e) {
              print('Python STDOUT Error: $e');
            },
          );

      // Python 서버의 표준 에러 Flutter 콘솔에 출력
      _pythonBackendProcess!.stderr
          .transform(utf8.decoder)
          .listen(
            (data) {
              print('Python STDERR: $data');
            },
            onError: (e) {
              print('Python STDERR Error: $e');
            },
          );

      // 프로세스가 예기치 않게 종료될 경우 로그
      _pythonBackendProcess!.exitCode.then((exitCode) {
        _pythonBackendProcess = null;
        print('Python Backend Exited with code: $exitCode');
        // 필요하면 재시작 로직 추가 가능
      });
    } catch (e) {
      print('Failed to start Python backend: $e');
      _pythonBackendProcess = null;
    }
  }

  /// Python 백엔드 종료 함수
  /// 앱 종료 시 반드시 호출 (안 그러면 프로세스가 남을 수 있음)
  static void stopPythonBackend() {
    if (_pythonBackendProcess != null) {
      print(
        'Attempting to kill Python backend (PID: ${_pythonBackendProcess!.pid})...',
      );
      _pythonBackendProcess!.kill();
      _pythonBackendProcess = null;
    } else {
      print('Python Backend is not running.');
    }
  }
}
