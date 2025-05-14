// lib/utils/web_helper.dart

import 'dart:convert'; // UTF-8 인코딩을 위한 라이브러리 임포트
import 'dart:html' as html; // 웹 환경의 HTML 기능을 사용하기 위한 라이브러리 임포트

// 웹 환경에서 Markdown 파일을 다운로드하는 함수
void downloadMarkdownWeb(String content, String fileName) { // <<-- 두 번째 인자로 String fileName 추가
  // 문자열 콘텐츠를 UTF-8 바이트 시퀀스로 인코딩
  final bytes = utf8.encode(content);
  // 인코딩된 바이트를 Blob 객체로 생성 (파일 데이터 표현)
  // 'text/markdown;charset=utf-8' MIME 타입을 명시해주는 것이 좋습니다.
  final blob = html.Blob([bytes], 'text/markdown;charset=utf-8');
  // Blob 객체로부터 URL 생성
  final url = html.Url.createObjectUrlFromBlob(blob);
  // 다운로드를 트리거하기 위한 앵커(a) HTML 엘리먼트 생성
  final anchor =
      html.AnchorElement(href: url) // Blob URL을 href 속성에 설정
        ..setAttribute("download", fileName) // <<-- 전달받은 fileName으로 파일 이름 설정
        ..click(); // 엘리먼트를 클릭하여 다운로드 시작
  // 사용 후 생성된 Blob URL 해제 (메모리 관리)
  html.Url.revokeObjectUrl(url);
}