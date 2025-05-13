import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import '../utils/ai_summarizer.dart';

/// 웹사이트를 크롤링하고, 본문을 Gemini로 요약하여 문자열로 반환
Future<String?> crawlSaveAndSummarize(
  String url, {
  String? customFileName,
}) async {
  try {
    // 네이버 블로그라면 iframe용 URL로 변환
    url = _adjustUrlIfNaverBlog(url);
    print('🌐 요청할 최종 URL: $url');

    // HTML 요청
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      print('❌ 요청 실패: ${response.statusCode}');
      return null;
    }

    // HTML 파싱
    final Document document = parser.parse(response.body);
    final StringBuffer mdBuffer = StringBuffer();

    // 제목 추출
    final title = document.querySelector('title')?.text.trim() ?? 'No Title';
    mdBuffer.writeln('# $title\n');

    // 헤딩 추출 (h1~h3)
    for (int i = 1; i <= 3; i++) {
      for (final h in document.querySelectorAll('h$i')) {
        final text = h.text.trim();
        if (text.isNotEmpty) mdBuffer.writeln('${'#' * i} $text\n');
      }
    }

    // 본문 텍스트 추출
    final tagsToExtract = ['p', 'div', 'article', 'section', 'span', 'li'];
    final Set<String> seenTexts = {};
    for (final tag in tagsToExtract) {
      for (final e in document.querySelectorAll(tag)) {
        final text = e.text.trim();
        if (text.isNotEmpty && !seenTexts.contains(text)) {
          mdBuffer.writeln('$text\n');
          seenTexts.add(text);
        }
      }
    }

    final fullText = mdBuffer.toString();
    print('📄 본문 전체 텍스트 길이: ${fullText.length}');

    // 요약 프롬프트 작성
    final prompt = '''
다음은 웹 페이지의 본문 텍스트입니다. 핵심 내용을 **한국어로 요약**해 주세요. 너무 짧지 않게 요약해주세요.

$fullText
''';

    // Gemini API 호출
    final String? summary = await callGeminiAPI(prompt);
    if (summary != null) {
      // print('✅ Gemini 요약 결과:\n$summary');
    } else {
      print('❌ 요약 실패');
    }

    return summary;
  } catch (e) {
    print('❌ 전체 에러 발생: $e');
    return null;
  }
}

/// 네이버 블로그인 경우 iframe 본문 URL로 변환
String _adjustUrlIfNaverBlog(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null &&
      uri.host.contains('blog.naver.com') &&
      uri.pathSegments.length >= 2) {
    final blogId = uri.pathSegments[0];
    final logNo = uri.pathSegments[1];
    return 'https://blog.naver.com/PostView.nhn?blogId=$blogId&logNo=$logNo';
  }
  return url;
}
