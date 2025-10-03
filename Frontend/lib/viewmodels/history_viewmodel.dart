// lib/viewmodels/history_viewmodel.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/auth_token.dart';
import '../layout/bottom_section_controller.dart';
import '../utils/ai_service.dart';
import '../providers/status_bar_provider.dart';

enum DateFilterPeriod { today, thisWeek, thisMonth, thisYear }

enum SortOrder { latest, oldest }

class HistoryViewModel with ChangeNotifier {
  List<Map<String, dynamic>> _visitHistory = [];
  List<Map<String, dynamic>> _filteredHistory = [];
  String _status = '방문 기록을 불러오세요.';
  bool _isLoading = false;
  final Set<String> _selectedUniqueKeys = {};

  String _searchQuery = '';
  DateFilterPeriod? _selectedPeriod;
  Set<String> _selectedDomains = {};
  Set<String> _selectedTags = {};
  SortOrder _sortOrder = SortOrder.latest;

  List<Map<String, dynamic>> get filteredHistory => _filteredHistory;
  String get status => _status;
  bool get isLoading => _isLoading;
  Set<String> get selectedUniqueKeys => _selectedUniqueKeys;
  bool get isFilterActive =>
      _searchQuery.isNotEmpty ||
      _selectedPeriod != null ||
      _selectedDomains.isNotEmpty ||
      _selectedTags.isNotEmpty;
  // ✨ [추가] View에서 정렬 순서를 알 수 있도록 getter 추가
  SortOrder get sortOrder => _sortOrder;

  @override
  void dispose() {
    _visitHistory.clear();
    _filteredHistory.clear();
    super.dispose();
  }

  void toggleItemSelection(String uniqueKey) {
    if (_selectedUniqueKeys.contains(uniqueKey)) {
      _selectedUniqueKeys.remove(uniqueKey);
    } else {
      _selectedUniqueKeys.add(uniqueKey);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedUniqueKeys.clear();
    notifyListeners();
  }

  // ✨ [수정] 필터링 후 정렬 로직 제거 (View에서 처리하도록 변경)
  void applyFilters({
    String? query,
    DateFilterPeriod? period,
    Set<String>? domains,
    Set<String>? tags,
    SortOrder? sortOrder,
    bool isPeriodChange = false,
  }) {
    _searchQuery = query ?? _searchQuery;
    if (isPeriodChange) {
      _selectedPeriod = period;
    }
    _selectedDomains = domains ?? _selectedDomains;
    _selectedTags = tags ?? _selectedTags;
    _sortOrder = sortOrder ?? _sortOrder;

    DateTime? startDate;
    final now = DateTime.now();

    if (_selectedPeriod != null) {
      switch (_selectedPeriod!) {
        case DateFilterPeriod.today:
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case DateFilterPeriod.thisWeek:
          startDate = now.subtract(Duration(days: now.weekday - 1));
          startDate = DateTime(startDate.year, startDate.month, startDate.day);
          break;
        case DateFilterPeriod.thisMonth:
          startDate = DateTime(now.year, now.month, 1);
          break;
        case DateFilterPeriod.thisYear:
          startDate = DateTime(now.year, 1, 1);
          break;
      }
    }

    final lowerCaseQuery = _searchQuery.toLowerCase();

    _filteredHistory =
        _visitHistory.where((item) {
          final title = item['title']?.toString().toLowerCase() ?? '';
          final url = item['url']?.toString().toLowerCase() ?? '';

          final textMatch =
              title.contains(lowerCaseQuery) || url.contains(lowerCaseQuery);
          if (!textMatch) return false;

          final timestampStr =
              item['timestamp'] ?? item['visitTime']?.toString();
          if (startDate != null) {
            if (timestampStr == null) return false;
            final visitDate = DateTime.parse(timestampStr).toLocal();
            if (visitDate.isBefore(startDate)) {
              return false;
            }
          }

          if (_selectedDomains.isNotEmpty) {
            try {
              final itemHost = Uri.parse(url).host;
              if (!_selectedDomains.any(
                (domain) => itemHost.contains(domain),
              )) {
                return false;
              }
            } catch (e) {
              return false;
            }
          }

          if (_selectedTags.isNotEmpty) {
            if (!_selectedTags.any(
              (tag) => title.contains(tag.toLowerCase()),
            )) {
              return false;
            }
          }

          return true;
        }).toList();

    notifyListeners();
  }

  Future<void> loadVisitHistory() async {
    if (_isLoading) return;

    _isLoading = true;
    _status = '방문 기록 불러오는 중...';
    _selectedUniqueKeys.clear();
    _visitHistory.clear();
    _filteredHistory.clear();
    notifyListeners();

    try {
      final googleAccessToken = await _getValidGoogleAccessToken();
      if (googleAccessToken == null) {
        throw Exception('Google 인증이 필요합니다.');
      }

      const folderName = 'memordo';
      final folderId = await _getFolderIdByName(folderName, googleAccessToken);
      if (folderId == null) {
        _visitHistory = [];
        _filteredHistory = [];
        _status = "'memordo' 폴더를 찾을 수 없습니다. 확장 프로그램에서 폴더를 생성해주세요.";
      } else {
        final url = Uri.parse(
          'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&fields=nextPageToken,files(id,name,createdTime,modifiedTime)',
        );

        final allFiles = await _fetchAllDriveFiles(url, googleAccessToken);

        if (allFiles.isEmpty) {
          _visitHistory = [];
          _filteredHistory = [];
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

          final uniqueKeys = <String>{};
          final List<Map<String, dynamic>> uniqueHistory = [];
          for (var item in allHistory) {
            final timestamp =
                item['timestamp'] ?? item['visitTime']?.toString() ?? '';
            final urlValue = item['url']?.toString() ?? '';
            final uniqueKey = '$timestamp-$urlValue';

            if (uniqueKeys.add(uniqueKey)) {
              uniqueHistory.add(item);
            }
          }

          uniqueHistory.sort((a, b) {
            final at = a['timestamp'] ?? a['visitTime']?.toString() ?? '';
            final bt = b['timestamp'] ?? b['visitTime']?.toString() ?? '';
            return bt.compareTo(at);
          });

          _visitHistory = uniqueHistory;
          _filteredHistory = List.from(_visitHistory);
          _status =
              _visitHistory.isEmpty
                  ? '방문 기록이 없습니다.'
                  : '총 ${_visitHistory.length}개의 방문 기록을 불러왔습니다.';
        }
      }
    } catch (e) {
      _status = '오류 발생: ${e.toString()}';
      _visitHistory = [];
      _filteredHistory = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> summarizeSelection(BuildContext context) async {
    // ... (기존과 동일)
    final bottomController = context.read<BottomSectionController>();
    final statusBar = context.read<StatusBarProvider>();

    if (bottomController.isLoading) return;

    if (_selectedUniqueKeys.length == 1) {
      final selectedUniqueKey = _selectedUniqueKeys.first;
      final lastHyphenIndex = selectedUniqueKey.lastIndexOf('-');

      String? selectedUrl;
      if (lastHyphenIndex != -1 &&
          lastHyphenIndex < selectedUniqueKey.length - 1) {
        selectedUrl = selectedUniqueKey.substring(lastHyphenIndex + 1);
      } else {
        selectedUrl = selectedUniqueKey;
      }

      if (selectedUrl != null && selectedUrl.isNotEmpty) {
        bottomController.setActiveTab(2);

        bottomController.setIsLoading(true);
        bottomController.updateSummary('URL 요약 중...\n$selectedUrl');

        final summary = await crawlAndSummarizeUrl(selectedUrl);
        if (!context.mounted) return;

        bottomController.updateSummary(summary ?? '요약에 실패했거나 내용이 없습니다.');
        bottomController.setIsLoading(false);

        if (summary == null ||
            summary.contains("오류") ||
            summary.contains("실패")) {
          statusBar.showStatusMessage(
            summary ?? 'URL 요약에 실패했습니다.',
            type: StatusType.error,
          );
        } else {
          statusBar.showStatusMessage(
            'URL 요약이 완료되었습니다.',
            type: StatusType.success,
          );
        }
      } else {
        statusBar.showStatusMessage(
          '유효한 URL을 찾을 수 없습니다.',
          type: StatusType.error,
        );
      }
    } else {
      statusBar.showStatusMessage(
        _selectedUniqueKeys.isEmpty
            ? '내용을 요약할 URL을 선택해주세요.'
            : '내용을 요약할 URL은 하나만 선택할 수 있습니다.',
        type: StatusType.info,
      );
    }
  }

  Future<List<dynamic>> _fetchAllDriveFiles(
    Uri initialUrl,
    String token,
  ) async {
    // ... (기존과 동일)
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
    // ... (기존과 동일)
    var googleAccessToken = await getStoredGoogleAccessToken();
    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      await refreshGoogleAccessTokenIfNeeded();
      googleAccessToken = await getStoredGoogleAccessToken();
    }
    return googleAccessToken;
  }

  Future<String?> _getFolderIdByName(String folderName, String token) async {
    // ... (기존과 동일)
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
    // ... (기존과 동일)
    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
    );
    final res = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode != 200) {
      if (res.statusCode == 404) {
        print('⚠️ 파일을 찾을 수 없습니다 (404): $fileId');
        return [];
      }
      throw Exception('파일 다운로드 실패 (상태: ${res.statusCode})');
    }

    final lines = const LineSplitter().convert(utf8.decode(res.bodyBytes));
    return lines
        .where((line) => line.trim().isNotEmpty)
        .map<Map<String, dynamic>>((line) {
          try {
            return jsonDecode(line);
          } catch (e) {
            print('JSON 파싱 오류: $line');
            return {};
          }
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
