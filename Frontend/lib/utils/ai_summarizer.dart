// ai_summarizer.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<String?> callGeminiAPI(String prompt) async {
  final apiKey = dotenv.env['GEMINI_API_KEY'];
  // print('👉 dotenv에서 불러온 Gemini API 키: $apiKey');
  if (apiKey == null) {
    print('❌ Gemini API 키가 설정되지 않았습니다.');
    return null;
  }

  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
  );

  final body = jsonEncode({
    "contents": [
      {
        "role": "user",
        "parts": [
          {"text": prompt},
        ],
      },
    ],
  });

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: body,
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final content = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
    return content?.toString().trim();
  } else {
    print("❌ Gemini 호출 실패: ${response.statusCode}");
    print(response.body);
    return null;
  }
}

// GPT 요약(현재 사용 X)
// Future<String?> callGptAPI(String prompt) async {
//   final apiKey = dotenv.env['OPENAI_API_KEY'];
//   print('👉 dotenv에서 불러온 API 키: $apiKey');
//   if (apiKey == null) {
//     print("❌ API 키가 설정되어 있지 않습니다.");
//     return null;
//   }

//   final response = await http.post(
//     Uri.parse('https://api.openai.com/v1/chat/completions'),
//     headers: {
//       'Content-Type': 'application/json',
//       'Authorization': 'Bearer $apiKey',
//     },
//     body: jsonEncode({
//       "model": "gpt-3.5-turbo",
//       "messages": [
//         {"role": "user", "content": prompt},
//       ],
//     }),
//   );

//   if (response.statusCode == 200) {
//     final data = jsonDecode(response.body);
//     return data['choices'][0]['message']['content'].trim();
//   } else {
//     print(response.body);
//     return null;
//   }
// }
