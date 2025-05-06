// 조건부 import만! 절대 dart:html 넣지 마세요!
export 'web_helper_stub.dart' if (dart.library.html) 'web_helper_real.dart';
