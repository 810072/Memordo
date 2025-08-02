// lib/viewmodels/history_viewmodel.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_token.dart'; // auth_token.dart의 함수들을 사용

/// 방문 기록(History) 화면의 상태와 비즈니스 로직을 관리하는 ViewModel
class HistoryViewModel with ChangeNotifier {
  List<Map<String, dynamic>> _visitHistory = [];
  String _status = '방문 기록을 불러오세요.';
  bool _isLoading = false;

  // View에서 접근할 수 있는 getter
  List<Map<String, dynamic>> get visitHistory => _visitHistory;
  String get status => _status;
  bool get isLoading => _isLoading;

  /// ViewModel이 생성될 때 데이터를 자동으로 불러옵니다.
  HistoryViewModel() {
    loadVisitHistory();
  }

  /// Google Drive에서 방문 기록 데이터를 불러오는 메인 함수
  Future<void> loadVisitHistory() async {
    _isLoading = true;
    _status = '방문 기록 불러오는 중...';
    notifyListeners(); // 상태 변경을 View에 알림

    try {
      final googleAccessToken = await _getValidGoogleAccessToken();
      if (googleAccessToken == null) {
        throw Exception('Google 인증이 필요합니다.');
      }

      const folderName = 'memordo';
      final folderId = await _getFolderIdByName(folderName, googleAccessToken);
      if (folderId == null) {
        throw Exception("'memordo' 폴더를 찾을 수 없습니다.");
      }

      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&pageSize=10',
      );

      final res = await http.get(
        url,
        headers: {'Authorization': 'Bearer $googleAccessToken'},
      );

      if (res.statusCode != 200) {
        throw Exception('파일 목록 조회 실패 (${res.statusCode})');
      }

      final data = jsonDecode(res.body);
      final files = data['files'] as List;
      if (files.isEmpty) {
        _visitHistory = [];
        _status = '방문 기록 파일(.jsonl)이 없습니다.';
      } else {
        final fileId = files[0]['id'];
        final history = await _downloadAndParseJsonl(googleAccessToken, fileId);
        _visitHistory = history;
        _status =
            history.isEmpty
                ? '방문 기록이 없습니다.'
                : '총 ${history.length}개의 방문 기록을 불러왔습니다.';
      }
    } catch (e) {
      _status = '오류 발생: ${e.toString()}';
      _visitHistory = []; // 오류 발생 시 목록 비우기
    } finally {
      _isLoading = false;
      notifyListeners(); // 작업 완료 후 상태 변경 알림
    }
  }

  // --- Helper Functions ---

  /// 유효한 Google Access Token을 가져오는 함수 (필요 시 갱신)
  Future<String?> _getValidGoogleAccessToken() async {
    var googleAccessToken = await getStoredGoogleAccessToken();
    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      await refreshGoogleAccessTokenIfNeeded();
      googleAccessToken = await getStoredGoogleAccessToken();
    }
    return googleAccessToken;
  }

  /// 폴더 이름으로 Google Drive에서 폴더 ID를 찾는 함수
  Future<String?> _getFolderIdByName(String folderName, String token) async {
    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files'
      '?q=mimeType=%27application/vnd.google-apps.folder%27+and+name=%27$folderName%27'
      '&fields=files(id,name)'
      '&pageSize=1',
    );

    final res = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final files = data['files'] as List;
      return files.isNotEmpty ? files[0]['id'] as String : null;
    }
    return null;
  }

  /// Google Drive에서 .jsonl 파일을 다운로드하고 파싱하는 함수
  Future<List<Map<String, dynamic>>> _downloadAndParseJsonl(
    String token,
    String fileId,
  ) async {
    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
    );
    final res = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode != 200) {
      throw Exception('파일 다운로드 실패 (상태: ${res.statusCode})');
    }

    final lines = const LineSplitter().convert(utf8.decode(res.bodyBytes));
    return lines
        .where((line) => line.trim().isNotEmpty)
        .map<Map<String, dynamic>>((line) {
          try {
            return jsonDecode(line);
          } catch (e) {
            return {};
          }
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
