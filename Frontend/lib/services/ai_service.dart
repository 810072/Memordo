import 'package:http/http.dart' as http;
import 'dart:convert';

class AiService {
  // 로컬 Python 서버 주소
  static const String _localBaseUrl = 'http://127.0.0.1:5001';

  Future<bool> initializeLocalAI(String apiKey) async {
    if (apiKey.isEmpty) {
      print('❌ API 키가 없어서 로컬 AI를 초기화할 수 없습니다.');
      return false;
    }

    final url = Uri.parse('$_localBaseUrl/api/initialize');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'api_key': apiKey}),
          )
          .timeout(const Duration(seconds: 5)); // 5초 타임아웃 설정

      if (response.statusCode == 200) {
        print('✅ 로컬 AI 백엔드 초기화 성공!');
        return true;
      } else {
        print('🟥 로컬 AI 백엔드 초기화 실패: ${response.body}');
        return false;
      }
    } catch (e) {
      print('🟥 로컬 AI 서버 연결 오류 (백그라운드에서 실행 중인지 확인 필요): $e');
      return false;
    }
  }
}
