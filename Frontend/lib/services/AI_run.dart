// import 'dart:io';
// import 'dart:convert';

/// 백엔드(Python 서버) 프로세스 자동 관리 로직이 제거되었습니다.
/// AI 기능을 사용하려면 Python 백엔드 서버를 수동으로 실행해야 합니다.
///
/// 프로젝트의 py 폴더로 이동한 후, 다음 명령어를 터미널에 입력하여 서버를 시작하세요:
/// python app.py
/// 또는
/// python3 app.py
class BackendService {
  // Python 백엔드 자동 실행/종료 관련 코드가 모두 제거되었습니다.
  // 이 클래스는 더 이상 사용되지 않지만, 다른 코드에서의 참조 오류를 방지하기 위해 비워둡니다.

  static Future<void> startPythonBackend() async {
    // 이 기능은 제거되었습니다.
    print('Python 백엔드 자동 실행 기능이 제거되었습니다. 서버를 수동으로 실행해주세요.');
  }

  static void stopPythonBackend() {
    // 이 기능은 제거되었습니다.
  }
}
