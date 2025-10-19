// lib/utils/ai_service.dart

import 'dart:convert'; // JSON 인코딩/디코딩
import 'dart:io'; // File I/O
import 'package:http/http.dart' as http; // HTTP 요청
import 'package:flutter_dotenv/flutter_dotenv.dart'; // .env 파일 로드
import 'package:html/parser.dart' as parser; // HTML 파싱
import 'package:path/path.dart' as p; // 경로 처리
import '../model/chat_message_model.dart'; // ✨ [추가] ChatMessage 모델 임포트

// --- 환경 설정 ---
final String _pythonBackendBaseUrl =
    dotenv.env['PYTHON_BACKEND_URL'] ?? 'http://localhost:5001';

// === Python 백엔드 API 호출 함수 ===

/// 범용 작업을 Python 백엔드에 요청합니다. (요약, 메모, 키워드, 일반 채팅 등)
// ✨ [수정] history 매개변수 추가
Future<String?> callBackendTask({
  required String taskType,
  required String text, // 현재 사용자 입력
  List<ChatMessage> history = const [], // ✨ 대화 기록 (기본값: 빈 리스트)
  String? model,
}) async {
  final Uri url = Uri.parse('$_pythonBackendBaseUrl/api/execute_task');
  final Map<String, String> headers = {'Content-Type': 'application/json'};

  // ✨ [수정] body에 history를 포함하도록 변경
  final Map<String, dynamic> body = {
    'task_type': taskType,
    'text': text, // 현재 사용자 입력은 text 필드로 유지
    // ✨ 대화 기록을 AI가 이해하는 형식으로 변환
    'messages':
        history.map((msg) {
          // ChatMessage의 "> " 접두사 제거
          final content =
              msg.isUser && msg.text.startsWith("> ")
                  ? msg.text.substring(2)
                  : msg.text;
          return {
            'role': msg.isUser ? 'user' : 'assistant',
            'content': content,
          };
        }).toList(),
  };

  if (model != null) {
    body['model'] = model;
  }

  print('[AI_SERVICE] Backend Task Request: ${url.toString()}');
  print(
    '[AI_SERVICE] Task Type: $taskType, Current Text: ${text.substring(0, text.length > 50 ? 50 : text.length)}...',
  );
  print('[AI_SERVICE] History length: ${history.length}'); // ✨ 기록 길이 로깅

  try {
    final response = await http
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 180));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
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
String _adjustUrlIfNaverBlog(String url) {
  // ... (기존 코드와 동일)
  final uri = Uri.tryParse(url);
  if (uri != null &&
      uri.host.contains('blog.naver.com') &&
      uri.pathSegments.isNotEmpty) {
    String blogId = "";
    String logNo = "";

    if (uri.pathSegments.length >= 2 &&
        uri.pathSegments[0].isNotEmpty &&
        uri.pathSegments[1].isNotEmpty) {
      blogId = uri.pathSegments[0];
      logNo = uri.pathSegments[1];
    } else if (uri.queryParameters.containsKey('blogId') &&
        uri.queryParameters.containsKey('logNo')) {
      blogId = uri.queryParameters['blogId']!;
      logNo = uri.queryParameters['logNo']!;
    } else {
      return url;
    }
    return 'https://blog.naver.com/PostView.naver?blogId=$blogId&logNo=$logNo&redirect=Dlog&widgetTypeCall=true&directAccess=false';
  }
  return url;
}

String _extractTextFromHtml(String htmlBody) {
  // ... (기존 코드와 동일)
  final document = parser.parse(htmlBody);
  final StringBuffer textBuffer = StringBuffer();
  final title = document.querySelector('title')?.text.trim() ?? '제목 없음';
  textBuffer.writeln('웹 페이지 제목: $title\n');
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
    if (mainContentLoaded) break;
  }
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
        textBuffer.writeln(elementText);
      }
    });
  }
  return textBuffer.toString().trim().replaceAll(RegExp(r'\n\s*\n'), '\n\n');
}

Future<String?> crawlAndSummarizeUrl(String urlString) async {
  // ... (기존 코드와 동일)
  print('[AI_SERVICE] Crawl & Summarize 요청 시작: $urlString');
  try {
    final String adjustedUrl = _adjustUrlIfNaverBlog(urlString);
    final response = await http
        .get(Uri.parse(adjustedUrl))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      String htmlBody;
      try {
        htmlBody = utf8.decode(response.bodyBytes);
      } catch (e) {
        try {
          htmlBody = latin1.decode(response.bodyBytes);
        } catch (e2) {
          return "HTML 인코딩을 처리할 수 없습니다.";
        }
      }

      final String extractedText = _extractTextFromHtml(htmlBody);
      if (extractedText.isEmpty || extractedText.length < 50) {
        return "웹 페이지에서 요약할 내용을 충분히 추출하지 못했습니다.";
      }
      const maxLengthForApi = 150000;
      String textToSummarize =
          extractedText.length > maxLengthForApi
              ? extractedText.substring(0, maxLengthForApi)
              : extractedText;

      // 요약에는 history가 필요 없으므로 빈 리스트 전달
      return await callBackendTask(
        taskType: "summarize",
        text: textToSummarize,
        history: [], // ✨
      );
    } else {
      return "웹 페이지를 가져오는 데 실패했습니다 (상태 코드: ${response.statusCode}).";
    }
  } catch (e) {
    return "웹 페이지 요약 중 오류가 발생했습니다: $e";
  }
}

// === 그래프 및 임베딩 관련 함수 ===
Future<Map<String, dynamic>?> generateGraphData(
  List<Map<String, String>> notes,
) async {
  // ... (기존 코드와 동일, 캐싱을 위해 직접 사용되기보다 graph_page에서 사용)
  final Uri url = Uri.parse('$_pythonBackendBaseUrl/api/generate-graph-data');
  final Map<String, String> headers = {
    'Content-Type': 'application/json; charset=UTF-8',
  };
  try {
    final response = await http
        .post(url, headers: headers, body: jsonEncode(notes))
        .timeout(const Duration(minutes: 5));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      final errorData = jsonDecode(utf8.decode(response.bodyBytes));
      return {
        'error':
            "백엔드 오류 (${response.statusCode}): ${errorData['error'] ?? '알 수 없는 오류'}",
      };
    }
  } catch (e) {
    return {'error': "통신 중 예외 발생: $e"};
  }
}

Future<Map<String, dynamic>?> getEmbeddingsForFiles(
  List<Map<String, String>> notesData,
) async {
  // ... (기존 코드와 동일)
  final Uri url = Uri.parse('$_pythonBackendBaseUrl/api/get-embeddings');
  final Map<String, String> headers = {'Content-Type': 'application/json'};
  try {
    final response = await http
        .post(url, headers: headers, body: jsonEncode(notesData))
        .timeout(const Duration(minutes: 5));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      return null;
    }
  } catch (e) {
    return null;
  }
}

// --- RAG 기능 ---
Future<String> _getNotesDirectory() async {
  // ... (기존 코드와 동일)
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null) throw Exception('홈 디렉토리를 찾을 수 없습니다.');
  return Platform.isMacOS
      ? p.join(home, 'Memordo_Notes')
      : p.join(home, 'Documents', 'Memordo_Notes');
}

// ✨ [수정] history 매개변수 추가
Future<Map<String, dynamic>?> callRagTask({
  required String query, // 현재 사용자 입력
  List<ChatMessage> history = const [], // ✨ 대화 기록 (기본값: 빈 리스트)
}) async {
  print('[AI_SERVICE] RAG Task Request: $query');
  print('[AI_SERVICE] RAG History length: ${history.length}'); // ✨ 로깅 추가

  try {
    // 1. 지식 베이스 파일 경로 확인 (변경 없음)
    final notesDir = await _getNotesDirectory();
    final embeddingsFile = File(p.join(notesDir, 'embeddings.json'));

    if (!await embeddingsFile.exists()) {
      return {
        'error':
            "오류: 지식 베이스 파일(embeddings.json)을 찾을 수 없습니다. 먼저 그래프 페이지에서 '임베딩 생성'을 실행해주세요.",
      };
    }

    // 2. 지식 베이스 파일 로드 (변경 없음)
    final cacheData = jsonDecode(await embeddingsFile.readAsString());
    final List<dynamic> nodes = cacheData['nodes'] ?? [];
    final List<dynamic> edges = cacheData['edges'] ?? [];

    if (nodes.isEmpty) {
      return {'error': "지식 베이스에 문서가 없습니다."};
    }

    // 3. 지식 베이스 노트의 최신 내용 읽기 (변경 없음)
    List<Map<String, String>> notesData = [];
    for (var node in nodes) {
      final fileName = node['id'];
      final file = File(p.join(notesDir, fileName));
      if (await file.exists()) {
        final content = await file.readAsString();
        notesData.add({'fileName': fileName, 'content': content});
      }
    }

    // 4. 백엔드 RAG API 호출
    final Uri url = Uri.parse('$_pythonBackendBaseUrl/api/rag_chat');
    final Map<String, String> headers = {'Content-Type': 'application/json'};

    // ✨ [수정] body에 history 포함
    final Map<String, dynamic> body = {
      'query': query, // 현재 사용자 입력
      'notes': notesData, // 검색 대상 문서들
      'edges': edges, // 문서 관계 정보
      // ✨ 대화 기록을 AI가 이해하는 형식으로 변환
      'messages':
          history.map((msg) {
            // ChatMessage의 "> " 접두사 제거
            final content =
                msg.isUser && msg.text.startsWith("> ")
                    ? msg.text.substring(2)
                    : msg.text;
            return {
              'role': msg.isUser ? 'user' : 'assistant',
              'content': content,
            };
          }).toList(),
    };

    final response = await http
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 180));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data;
    } else {
      final errorData = jsonDecode(utf8.decode(response.bodyBytes));
      print(
        '[AI_SERVICE] ❌ RAG Task Failed (${response.statusCode}): $errorData',
      );
      return {
        'error':
            "백엔드 오류 (${response.statusCode}): ${errorData['error'] ?? '알 수 없는 오류'}",
      };
    }
  } catch (e) {
    print('[AI_SERVICE] ❌ Exception during RAG Task: $e');
    return {'error': "RAG 작업 중 예외가 발생했습니다: $e"};
  }
}
