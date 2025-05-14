// lib/services/google_drive_auth_platform.dart
// 플랫폼별 Google Drive 인증 구현을 위한 조건부 import 파일

import 'package:flutter/foundation.dart' show kIsWeb;

// dart:library.html 라이브러리가 사용 가능하면 (즉, 웹 환경이면)
// 'google_drive_web_auth.dart'를 임포트하고 그 안에 있는 GoogleDriveAuthWeb 클래스를
// GoogleDriveAuth 라는 이름으로 노출합니다.
// 그렇지 않으면 (웹이 아닌 환경이면) 'google_drive_auth.dart'를 임포트하고
// 그 안에 있는 GoogleDriveAuth 클래스를 그대로 노출합니다.
// 이렇게 하면 이 파일을 임포트하는 다른 코드에서는 항상 'GoogleDriveAuth'라는 이름으로
// 플랫폼별 구현체를 사용할 수 있습니다.
// lib/services/google_drive_platform.dart

export 'google_drive_web_auth.dart'
    if (dart.library.io) 'google_drive_auth.dart';

// 이 파일을 임포트하는 다른 코드에서는 다음과 같이 사용합니다:
// import 'package:your_app_name/services/google_drive_auth_platform.dart';
// final auth = GoogleDriveAuth(); // 이 시점에서 플랫폼에 맞는 구현체 인스턴스가 생성됩니다.
