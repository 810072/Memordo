// lib/viewmodels/history_viewmodel.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_token.dart';

class HistoryViewModel with ChangeNotifier {
  List<Map<String, dynamic>> _visitHistory = [];
  String _status = '방문 기록을 불러오세요.';
  bool _isLoading = false;

  List<Map<String, dynamic>> get visitHistory => _visitHistory;
  String get status => _status;
  bool get isLoading => _isLoading;

  HistoryViewModel() {
    loadVisitHistory();
  }

  Future<void> loadVisitHistory() async {
    _isLoading = true;
    _status = '방문 기록 불러오는 중...';
    notifyListeners();

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
        'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&fields=nextPageToken,files(id,name,createdTime,modifiedTime)',
      );

      final allFiles = await _fetchAllDriveFiles(url, googleAccessToken);

      if (allFiles.isEmpty) {
        _visitHistory = [];
        _status = '방문 기록 파일(.jsonl)이 없습니다.';
      } else {
        final List<Map<String, dynamic>> allHistory = [];
        await Future.wait(
          allFiles.map((file) async {
            final historyPart = await _downloadAndParseJsonl(
              googleAccessToken,
              file['id'],
            );
            allHistory.addAll(historyPart);
          }),
        );

        allHistory.sort((a, b) {
          final at = a['timestamp'] ?? a['visitTime']?.toString() ?? '';
          final bt = b['timestamp'] ?? b['visitTime']?.toString() ?? '';
          return bt.compareTo(at);
        });

        _visitHistory = allHistory;
        _status =
            allHistory.isEmpty
                ? '방문 기록이 없습니다.'
                : '총 ${allHistory.length}개의 방문 기록을 불러왔습니다.';
      }
    } catch (e) {
      _status = '오류 발생: ${e.toString()}';
      _visitHistory = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<dynamic>> _fetchAllDriveFiles(
    Uri initialUrl,
    String token,
  ) async {
    List<dynamic> allFiles = [];
    String? nextPageToken;

    do {
      final urlWithToken =
          nextPageToken == null
              ? initialUrl
              : initialUrl.replace(
                queryParameters: {
                  ...initialUrl.queryParameters,
                  'pageToken': nextPageToken,
                },
              );

      final res = await http.get(
        urlWithToken,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) {
        throw Exception('파일 목록 조회 실패 (${res.statusCode})');
      }

      final data = jsonDecode(res.body);
      allFiles.addAll(data['files'] as List);
      nextPageToken = data['nextPageToken'];
    } while (nextPageToken != null);

    return allFiles;
  }

  Future<String?> _getValidGoogleAccessToken() async {
    var googleAccessToken = await getStoredGoogleAccessToken();
    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      await refreshGoogleAccessTokenIfNeeded();
      googleAccessToken = await getStoredGoogleAccessToken();
    }
    return googleAccessToken;
  }

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
