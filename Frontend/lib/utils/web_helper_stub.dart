// 웹이 아닌 환경에서는 이 함수가 실행됨
// 웹 환경에서 사용되는 downloadMarkdownWeb 함수의 스텁(가짜) 구현입니다.
// 실제 웹 환경이 아닐 때는 이 함수가 호출되어도 아무런 작업을 하지 않습니다.
void downloadMarkdownWeb(String content, String fileName) {
  // 아무 작업도 하지 않음
}

/// 웹이 아닌 환경에서는 이 함수가 실행됨 (스텁 구현)
Future<String?> pickFileWeb() async {
  return null; // 웹이 아닌 환경에서는 파일 선택 기능 없음
}
