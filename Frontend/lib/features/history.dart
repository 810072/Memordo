// lib/features/history.dart
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../layout/main_layout.dart'; // ✅ MainLayout 임포트
import '../widgets/ai_summary_widget.dart'; // ✅ AiSummaryWidget 임포트
import '../utils/ai_service.dart';
import '../layout/ai_summary_controller.dart'; // ✅ AiSummaryController 임포트
import '../services/auth_token.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../auth/login_page.dart';
import 'page_type.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';
  List<Map<String, dynamic>> _visitHistory = [];
  final Set<String> _selectedTimestamps = {};
  String _status = '불러오는 중...';
  bool _showSummary = false;

  @override
  void initState() {
    super.initState();
    _checkTokensThenLoad();
  }

  // ... (_checkTokensThenLoad, _loadVisitHistory, _getFolderIdByName, _downloadAndParseJsonl, _signInWithGoogle, _waitForCode, _navigateToLogin, _showSnackBar 함수는 기존 코드 유지) ...
  Future<void> _checkTokensThenLoad() async {
    /* ... */
  }
  Future<void> _loadVisitHistory() async {
    /* ... */
  }
  Future<String?> _getFolderIdByName(String folderName, String token) async {
    /* ... */
    return null;
  }

  Future<List<Map<String, dynamic>>> _downloadAndParseJsonl(
    String token,
    String fileId,
  ) async {
    /* ... */
    return [];
  }

  Future<void> _signInWithGoogle() async {
    /* ... */
  }
  Future<String?> _waitForCode(String redirectUri) async {
    /* ... */
    return null;
  }

  void _navigateToLogin() {
    /* ... */
  }
  void _showSnackBar(String message) {
    /* ... */
  }

  void _handleSummarizeAction() async {
    final aiController = Provider.of<AiSummaryController>(
      context,
      listen: false,
    );
    if (aiController.isLoading) return;

    if (_selectedTimestamps.length == 1) {
      // ... (기존 요약 로직 유지) ...
      // ✅ 요약 위젯 표시
      setState(() {
        _showSummary = true;
      });
      // ... (aiController 업데이트) ...
    } else {
      // ... (SnackBar 표시) ...
      // ✅ 요약 실패 시 요약 위젯 숨기기 (선택 사항)
      // setState(() { _showSummary = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (groupedByDate, sortedDates 계산 동일) ...
    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var item in _visitHistory) {
      final timestamp = item['timestamp'] ?? item['visitTime']?.toString();
      if (timestamp == null || timestamp.length < 10) continue;
      final date = timestamp.substring(0, 10);
      groupedByDate.putIfAbsent(date, () => []).add(item);
    }
    final sortedDates =
        groupedByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return MainLayout(
      // ✅ MainLayout 사용
      activePage: PageType.history,
      child: Column(
        children: [
          Container(
            // ✅ 수정된 Container
            height: 50,
            // color: Colors.white, // <--- 이 줄 삭제
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white, // <--- color 속성을 BoxDecoration 안으로 이동
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '방문 기록',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.summarize_outlined, size: 18),
                  label: const Text("선택 항목 요약"),
                  onPressed: _handleSummarizeAction, // 이 함수는 그대로 유지
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3d98f4),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              // ✅ 히스토리와 요약을 가로로 배치
              children: [
                Expanded(
                  flex: _showSummary ? 2 : 3, // ✅ 요약 위젯 보일 때 너비 조정
                  child: Container(
                    margin: const EdgeInsets.all(16.0),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child:
                        _visitHistory.isEmpty
                            ? Center(child: Text(_status))
                            : ListView.builder(
                              // ✅ ListTile 스타일 개선
                              itemCount: sortedDates.length,
                              itemBuilder: (context, index) {
                                final date = sortedDates[index];
                                final itemsOnDate =
                                    groupedByDate[date]!..sort((a, b) {
                                      // 날짜 내 시간 역순 정렬 (기존 로직 유지)
                                      final at =
                                          a['timestamp'] ??
                                          a['visitTime']?.toString();
                                      final bt =
                                          b['timestamp'] ??
                                          b['visitTime']?.toString();
                                      if (at == null && bt == null) return 0;
                                      if (at == null) return 1; // null을 뒤로
                                      if (bt == null) return -1; // null을 뒤로
                                      return bt.compareTo(at); // 최신 시간이 위로
                                    });

                                return Padding(
                                  // ✅ 163번째 줄 근처의 Padding 위젯
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12.0,
                                    horizontal: 16.0,
                                  ), // ✅ padding 인자 수정/추가 (좌우 패딩도 추가)
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 날짜 헤더
                                      Text(
                                        _formatDateKorean(date),
                                        style: const TextStyle(
                                          fontSize: 16, // 날짜 폰트 크기 조정
                                          fontWeight: FontWeight.bold,
                                          color:
                                              Colors
                                                  .blueGrey, // 기존 색상 유지 또는 테마 색상 사용
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 8,
                                      ), // 날짜와 첫 아이템 간 간격
                                      // 해당 날짜의 방문 기록 아이템들
                                      ...itemsOnDate.map((item) {
                                        final title =
                                            item['title']?.toString() ??
                                            item['url']?.toString() ??
                                            '제목 없음';
                                        final url =
                                            item['url']?.toString() ?? '';
                                        final timestamp =
                                            item['timestamp'] ??
                                            item['visitTime']?.toString();
                                        final time = _formatTime(timestamp);
                                        final bool isChecked =
                                            _selectedTimestamps.contains(
                                              timestamp,
                                            );

                                        return Card(
                                          // 각 아이템을 Card로 감싸 시각적 개선
                                          elevation: 1.0, // 약간의 그림자
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 4.0,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8.0,
                                            ),
                                          ),
                                          color:
                                              isChecked
                                                  ? Colors.deepPurple.shade50
                                                  : Colors.white,
                                          child: ListTile(
                                            leading: Checkbox(
                                              value: isChecked,
                                              activeColor: Colors.deepPurple,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onChanged: (bool? checked) {
                                                if (timestamp == null) return;
                                                setState(() {
                                                  if (checked == true) {
                                                    _selectedTimestamps.add(
                                                      timestamp,
                                                    );
                                                  } else {
                                                    _selectedTimestamps.remove(
                                                      timestamp,
                                                    );
                                                  }
                                                });
                                              },
                                            ),
                                            title: Text(
                                              title,
                                              style: const TextStyle(
                                                fontSize: 14, // 아이템 제목 폰트 크기 조정
                                                fontWeight: FontWeight.w500,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            subtitle:
                                                url.isNotEmpty
                                                    ? RichText(
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                      text: TextSpan(
                                                        text: url,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              Colors
                                                                  .blue
                                                                  .shade700, // 링크 색상 조정
                                                          decoration:
                                                              TextDecoration
                                                                  .underline,
                                                          decorationColor:
                                                              Colors
                                                                  .blue
                                                                  .shade700,
                                                        ),
                                                        recognizer:
                                                            TapGestureRecognizer()
                                                              ..onTap = () async {
                                                                if (url
                                                                    .isNotEmpty) {
                                                                  final uri =
                                                                      Uri.tryParse(
                                                                        url,
                                                                      );
                                                                  if (uri !=
                                                                          null &&
                                                                      await canLaunchUrl(
                                                                        uri,
                                                                      )) {
                                                                    await launchUrl(
                                                                      uri,
                                                                      mode:
                                                                          LaunchMode
                                                                              .externalApplication,
                                                                    );
                                                                  } else {
                                                                    if (mounted) {
                                                                      ScaffoldMessenger.of(
                                                                        context,
                                                                      ).showSnackBar(
                                                                        SnackBar(
                                                                          content: Text(
                                                                            'URL을 열 수 없습니다: $url',
                                                                          ),
                                                                        ),
                                                                      );
                                                                    }
                                                                  }
                                                                }
                                                              },
                                                      ),
                                                    )
                                                    : null,
                                            trailing: Text(
                                              time,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 8.0,
                                                  vertical: 4.0,
                                                ), // ListTile 내부 패딩 조정
                                            dense: true,
                                            onTap: () {
                                              // ListTile 전체 클릭 시에도 체크박스 토글
                                              if (timestamp == null) return;
                                              setState(() {
                                                if (isChecked) {
                                                  _selectedTimestamps.remove(
                                                    timestamp,
                                                  );
                                                } else {
                                                  _selectedTimestamps.add(
                                                    timestamp,
                                                  );
                                                }
                                              });
                                            },
                                          ),
                                        );
                                      }).toList(),

                                      // 날짜 그룹 사이에 구분선 (마지막 그룹 제외)
                                      if (index < sortedDates.length - 1)
                                        const Divider(
                                          height: 30,
                                          thickness: 0.5,
                                          indent: 16,
                                          endIndent: 16,
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                  ),
                ),
                if (_showSummary) // ✅ 요약 위젯 조건부 표시
                  Expanded(
                    flex: 1,
                    child: Container(
                      margin: const EdgeInsets.only(
                        top: 16.0,
                        right: 16.0,
                        bottom: 16.0,
                      ),
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: const AiSummaryWidget(), // ✅ AI 요약 위젯 사용
                    ),
                  ),
              ],
            ),
          ),
          // CollapsibleBottomSection 제거
        ],
      ),
    );
  }

  // ... (_formatDateKorean, _formatTime 함수 동일) ...
  String _formatDateKorean(String yyyyMMdd) {
    /* ... */
    return yyyyMMdd;
  }

  String _formatTime(String? isoString) {
    /* ... */
    return '';
  }
}
