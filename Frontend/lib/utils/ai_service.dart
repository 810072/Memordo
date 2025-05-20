// lib/services/ai_service.dart

import 'dart:convert'; // JSON 인코딩/디코딩
import 'package:http/http.dart' as http; // HTTP 요청
import 'package:flutter_dotenv/flutter_dotenv.dart'; // .env 파일 로드 (백엔드 URL 등)
import 'package:html/parser.dart' as parser; // HTML 파싱
// import 'package:html/dom.dart'; // 필요시 사용 (보통 parser를 통해 접근)

// --- 환경 설정 ---
// .env 파일에 PYTHON_BACKEND_URL=http://10.0.2.2:5000 와 같이 정의
final String _pythonBackendBaseUrl =
    dotenv.env['PYTHON_BACKEND_URL'] ?? 'http://localhost:5001';
// === Python 백엔드 API 호출 함수 ===

/// 범용 작업을 Python 백엔드에 요청합니다. (요약, 메모, 키워드, 일반 채팅 등)
///
/// [taskType]: 백엔드에서 정의된 작업 유형 (예: "summarize", "keyword", "chat")
/// [text]: 처리할 텍스트 내용
/// [model]: 사용할 AI 모델 (선택 사항, 백엔드 기본값 사용 가능)
Future<String?> callBackendTask({
  required String taskType,
  required String text,
  String? model,
}) async {
  final Uri url = Uri.parse('$_pythonBackendBaseUrl/api/execute_task');
  final Map<String, String> headers = {'Content-Type': 'application/json'};
  final Map<String, dynamic> body = {'task_type': taskType, 'text': text};
  if (model != null) {
    body['model'] = model;
  }

  print('[AI_SERVICE] Backend Task Request: ${url.toString()}');
  print(
    '[AI_SERVICE] Task Type: $taskType, Text (간략히): ${text.substring(0, text.length > 50 ? 50 : text.length)}...',
  );

  try {
    final response = await http
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 180)); // AI 작업은 시간이 걸릴 수 있으므로 타임아웃 설정

    if (response.statusCode == 200) {
      final data = jsonDecode(
        utf8.decode(response.bodyBytes),
      ); // 한글 응답을 위해 UTF-8 디코딩
      final String? result = data['result']?.toString().trim();
      print(
        '[AI_SERVICE] Backend Task Success. Result (간략히): ${result?.substring(0, result.length > 50 ? 50 : result.length)}...',
      );
      return result;
    } else {
      print(
        '[AI_SERVICE] ❌ Backend Task Failed (${response.statusCode}) for task: $taskType',
      );
      try {
        final errorData = jsonDecode(utf8.decode(response.bodyBytes));
        print('[AI_SERVICE] Error Body: $errorData');
        return "백엔드 오류 (${response.statusCode}): ${errorData['error'] ?? response.reasonPhrase}";
      } catch (e) {
        print('[AI_SERVICE] Error Body (raw): ${response.body}');
        return "백엔드 오류 (${response.statusCode}): 응답 파싱 실패";
      }
    }
  } catch (e) {
    print(
      '[AI_SERVICE] ❌ Exception during Backend Task Call for task $taskType: $e',
    );
    return "통신 중 예외 발생: $e";
  }
}

// === 웹 크롤링 및 요약 기능 ===

/// 네이버 블로그 URL인 경우 iframe 내부의 실제 컨텐츠 URL로 조정합니다.
String _adjustUrlIfNaverBlog(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null &&
      uri.host.contains('blog.naver.com') &&
      uri.pathSegments.isNotEmpty) {
    // pathSegments가 최소 1개 이상 있어야 logNo 등을 참조 가능
    String blogId = "";
    String logNo = "";

    if (uri.pathSegments.length >= 2 &&
        uri.pathSegments[0].isNotEmpty &&
        uri.pathSegments[1].isNotEmpty) {
      blogId = uri.pathSegments[0];
      logNo = uri.pathSegments[1];
    } else if (uri.queryParameters.containsKey('blogId') &&
        uri.queryParameters.containsKey('logNo')) {
      // 모바일 URL 등에서 blogId와 logNo가 쿼리 파라미터로 오는 경우
      blogId = uri.queryParameters['blogId']!;
      logNo = uri.queryParameters['logNo']!;
    } else {
      // blogId와 logNo를 찾을 수 없는 경우 원본 URL 반환
      print('[AI_SERVICE] 네이버 블로그 URL 형식이지만 blogId, logNo 추출 불가: $url');
      return url;
    }
    // 네이버는 PostView.naver로 요청하면 내부적으로 리다이렉션 처리하기도 함.
    // 혹은 직접 PostView.nhn 이나 최신 포맷으로 구성.
    // 좀 더 안정적인 URL 구성이 필요할 수 있음. (예: PostView.naver? ...)
    return 'https://blog.naver.com/PostView.naver?blogId=$blogId&logNo=$logNo&redirect=Dlog&widgetTypeCall=true&directAccess=false';
  }
  return url;
}

/// 웹 페이지의 텍스트를 추출합니다. (간단한 버전)
String _extractTextFromHtml(String htmlBody) {
  final document = parser.parse(htmlBody);
  final StringBuffer textBuffer = StringBuffer();

  // 제목 추출
  final title = document.querySelector('title')?.text.trim() ?? '제목 없음';
  textBuffer.writeln('웹 페이지 제목: $title\n');

  // 주요 콘텐츠 영역 우선 탐색 (더 많은 선택자 추가 가능)
  final mainSelectors = [
    'article',
    'main',
    '.post-content',
    '#articleBodyContents',
    '#content',
    '.tds-main',
  ];
  bool mainContentLoaded = false;
  for (String selector in mainSelectors) {
    document.querySelectorAll(selector).forEach((element) {
      // 스크립트, 스타일 태그 내용 제외
      element
          .querySelectorAll(
            'script, style, noscript, iframe, nav, footer, header, .advertisement, .ads',
          )
          .forEach((e) => e.remove());
      String elementText = element.text.trim().replaceAllMapped(
        RegExp(r'\s{2,}'),
        (match) => ' ',
      );
      if (elementText.isNotEmpty) {
        textBuffer.writeln(elementText);
        mainContentLoaded = true;
      }
    });
    if (mainContentLoaded) break; // 주요 영역 중 하나라도 찾으면 중단
  }

  // 주요 콘텐츠가 없으면 body 전체에서 p, div 태그 위주로 추출 (노이즈 많을 수 있음)
  if (!mainContentLoaded) {
    document.body?.querySelectorAll('p, div, li, span').forEach((element) {
      element
          .querySelectorAll(
            'script, style, noscript, iframe, nav, footer, header, .advertisement, .ads',
          )
          .forEach((e) => e.remove());
      String elementText = element.text.trim().replaceAllMapped(
        RegExp(r'\s{2,}'),
        (match) => ' ',
      );
      if (elementText.length > 30) {
        // 너무 짧은 텍스트는 제외 (노이즈 줄이기)
        textBuffer.writeln(elementText);
      }
    });
  }

  String result = textBuffer.toString().trim();
  // 연속된 개행 문자 정리
  result = result.replaceAll(RegExp(r'\n\s*\n'), '\n\n');
  return result;
}

/// URL에서 웹 페이지 내용을 크롤링하고, 백엔드를 통해 요약합니다.
Future<String?> crawlAndSummarizeUrl(String urlString) async {
  print('[AI_SERVICE] Crawl & Summarize 요청 시작: $urlString');
  try {
    final String adjustedUrl = _adjustUrlIfNaverBlog(urlString);
    print('[AI_SERVICE] 🌐 최종 크롤링 URL: $adjustedUrl');

    final response = await http
        .get(Uri.parse(adjustedUrl))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      print(
        '[AI_SERVICE] ✅ 웹 페이지 HTML 수신 성공 (길이: ${response.bodyBytes.length}). 파싱 및 텍스트 추출 중...',
      );
      // UTF-8로 먼저 시도, 안되면 meta 태그의 charset 확인 또는 다른 인코딩 시도 (http 패키지는 보통 알아서 처리)
      String htmlBody;
      try {
        htmlBody = utf8.decode(response.bodyBytes);
      } catch (e) {
        print('[AI_SERVICE] UTF-8 디코딩 실패, latin1으로 재시도...');
        try {
          htmlBody = latin1.decode(response.bodyBytes);
        } catch (e2) {
          print('[AI_SERVICE] ❌ HTML 인코딩 처리 실패: $e2');
          return "HTML 인코딩을 처리할 수 없습니다.";
        }
      }

      final String extractedText = _extractTextFromHtml(htmlBody);

      if (extractedText.isEmpty || extractedText.length < 50) {
        // 요약할 내용이 너무 적은 경우
        print('[AI_SERVICE] ⚠️ 웹 페이지에서 요약할 충분한 텍스트를 추출하지 못했습니다.');
        return "웹 페이지에서 요약할 내용을 충분히 추출하지 못했습니다.";
      }

      print(
        '[AI_SERVICE] 📄 추출된 텍스트 길이: ${extractedText.length}. 백엔드에 요약 요청...',
      );

      // 길이 제한 (백엔드 또는 Gemini 모델의 최대 토큰 제한 고려)
      const maxLengthForApi = 150000; // 예시: 15만자 (실제로는 토큰 기반이어야 함)
      String textToSummarize = extractedText;
      if (extractedText.length > maxLengthForApi) {
        textToSummarize = extractedText.substring(0, maxLengthForApi);
        print('[AI_SERVICE] ✂️ 텍스트가 너무 길어 ${maxLengthForApi}자로 제한하여 요약 요청합니다.');
      }

      // 백엔드의 'summarize' 작업 유형 사용
      return await callBackendTask(
        taskType: "summarize", // Flask 백엔드에서 정의한 작업 유형
        text: textToSummarize,
      );
    } else {
      print(
        '[AI_SERVICE] ❌ 웹 페이지 요청 실패: ${response.statusCode} for $adjustedUrl',
      );
      return "웹 페이지를 가져오는 데 실패했습니다 (상태 코드: ${response.statusCode}).";
    }
  } catch (e, s) {
    print('[AI_SERVICE] ❌ 크롤링 및 요약 중 전체 에러 발생: $e');
    print(s); // 스택 트레이스 출력
    return "웹 페이지 요약 중 오류가 발생했습니다: $e";
  }
}
