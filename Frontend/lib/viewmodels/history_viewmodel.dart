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

  // ✨ [추가] 페이지네이션 관련 변수
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalResults = 0;
  static const int _pageSize = 100; // 한 번에 가져올 개수

  List<Map<String, dynamic>> get filteredHistory => _filteredHistory;
  String get status => _status;
  bool get isLoading => _isLoading;
  Set<String> get selectedUniqueKeys => _selectedUniqueKeys;
  bool get isFilterActive =>
      _searchQuery.isNotEmpty ||
      _selectedPeriod != null ||
      _selectedDomains.isNotEmpty ||
      _selectedTags.isNotEmpty;
  SortOrder get sortOrder => _sortOrder;

  // ✨ [추가] 페이지네이션 정보 Getter
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalResults => _totalResults;
  bool get hasMorePages => _currentPage < _totalPages;

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

  /// ✨ [새로운 함수] 서버에서 방문 기록 불러오기
  Future<void> loadVisitHistory(
    BuildContext context, {
    bool loadMore = false,
  }) async {
    if (_isLoading) return;

    _isLoading = true;

    // 초기 로드인 경우에만 상태 초기화
    if (!loadMore) {
      _status = '방문 기록 불러오는 중...';
      _selectedUniqueKeys.clear();
      _visitHistory.clear();
      _filteredHistory.clear();
      _currentPage = 1;
    } else {
      // 더 불러오기인 경우 페이지 증가
      _currentPage++;
    }

    notifyListeners();

    try {
      // ✨ 서버 API 호출 (authorizedRequest 사용)
      final url = Uri.parse(
        'https://aidoctorgreen.com/memo/api/h/history/list',
      ).replace(
        queryParameters: {
          'page': _currentPage.toString(),
          'limit': _pageSize.toString(),
        },
      );

      print('[HistoryViewModel] 서버에서 방문 기록 요청: $url');

      final response = await authorizedRequest(
        url,
        context: context,
        method: 'GET',
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic> results = data['results'] ?? [];

        // 페이지네이션 정보 업데이트
        _totalPages = data['total_pages'] ?? 1;
        _totalResults = data['total_results'] ?? 0;

        // 서버 응답 데이터를 기존 형식으로 변환
        final List<Map<String, dynamic>> newHistory =
            results.map((item) {
              return {
                'url': item['url'],
                'title': item['title'] ?? 'No Title',
                'timestamp': item['timestamp'],
              };
            }).toList();

        if (loadMore) {
          // 더 불러오기: 기존 데이터에 추가
          _visitHistory.addAll(newHistory);
        } else {
          // 초기 로드: 전체 교체
          _visitHistory = newHistory;
        }

        // 중복 제거 (uniqueKey 기준)
        final uniqueKeys = <String>{};
        final List<Map<String, dynamic>> uniqueHistory = [];
        for (var item in _visitHistory) {
          final timestamp = item['timestamp'] ?? '';
          final urlValue = item['url']?.toString() ?? '';
          final uniqueKey = '$timestamp-$urlValue';

          if (uniqueKeys.add(uniqueKey)) {
            uniqueHistory.add(item);
          }
        }

        _visitHistory = uniqueHistory;
        _filteredHistory = List.from(_visitHistory);

        _status =
            _visitHistory.isEmpty
                ? '방문 기록이 없습니다.'
                : '총 ${_totalResults}개의 방문 기록 중 ${_visitHistory.length}개 로드됨.';

        print(
          '[HistoryViewModel] 로드 완료: ${_visitHistory.length}개 (${_currentPage}/$_totalPages 페이지)',
        );
      } else {
        final errorData = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(
          '서버 오류 (${response.statusCode}): ${errorData['message'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      _status = '오류 발생: ${e.toString()}';
      _visitHistory = [];
      _filteredHistory = [];
      print('[HistoryViewModel] ❌ 로드 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ✨ [새로운 함수] 다음 페이지 불러오기
  Future<void> loadMoreHistory(BuildContext context) async {
    if (!hasMorePages || _isLoading) return;
    await loadVisitHistory(context, loadMore: true);
  }

  Future<void> summarizeSelection(BuildContext context) async {
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
}
