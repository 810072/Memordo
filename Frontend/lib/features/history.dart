// lib/features/history.dart
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../layout/left_sidebar_layout.dart'; // 이 파일의 실제 경로 확인 필요
import '../layout/bottom_section.dart'; // 이 파일의 실제 경로 확인 필요
// import '../services/google_drive_auth.dart'; // 이 파일의 실제 경로 확인 필요
import '../services/google_drive_platform.dart';
// import '../utils/web_crawler.dart'; // 기존 import 삭제
import '../utils/ai_service.dart'; // 새로 만든 ai_service.dart import (경로 확인!)
// import 'package:flutter_dotenv/flutter_dotenv.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _visitHistory = [];
  final Set<String> _selectedTimestamps = {};
  String _status = '불러오는 중...';
  final folderId =
      '18gvXku0NzRbFrWJtsuI52dX0IJq_IE1f'; // Google Drive 폴더 ID는 필요시 사용
  // 실제 사용하시는 폴더 ID로 유지하거나, 다른 방식으로 관리할 수 있습니다.
  // 예시에서는 Google Drive 연동 로직은 그대로 유지합니다.
  // final String folderId = 'YOUR_GOOGLE_DRIVE_FOLDER_ID'; // 여기에 실제 폴더 ID를 입력하세요.
  final GlobalKey<CollapsibleBottomSectionState> _bottomSectionKey =
      GlobalKey();

  bool _isSummarizing = false; // 요약 중 상태 표시를 위한 변수

  @override
  void initState() {
    super.initState();
    _loadVisitHistory();
  }

  Future<void> _loadVisitHistory() async {
    if (!mounted) return; // 위젯이 dispose된 경우 setState 호출 방지
    setState(() => _status = '방문 기록 불러오는 중...');
    final auth = GoogleDriveAuth(); // 공통 코드로 가능
    // await auth.logout(); // 필요시 로그아웃 테스트
    final token = await auth.getAccessToken();
    if (token == null) {
      if (!mounted) return;
      setState(() => _status = 'Google 로그인에 실패했습니다. 다시 시도해주세요.');
      return;
    }

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&pageSize=10', // pageSize 늘려서 여러 파일 고려 가능
      );
      final res = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        if (!mounted) return;
        await auth.logout();
        setState(
          () => _status = 'Google Drive 파일 목록 가져오기 실패 (상태: ${res.statusCode})',
        );
        print('Drive API Error: ${res.body}');
        return;
      }

      final data = jsonDecode(res.body);
      if ((data['files'] as List).isEmpty) {
        if (!mounted) return;
        setState(() => _status = '방문기록(.jsonl) 파일을 찾을 수 없습니다.');
        return;
      }

      // 여러 .jsonl 파일을 병합하거나, 가장 최신 파일 하나만 사용할 수 있습니다.
      // 여기서는 가장 최신 파일 하나를 사용합니다.
      final fileId = data['files'][0]['id'];
      final history = await _downloadAndParseJsonl(token, fileId);

      if (!mounted) return;
      setState(() {
        _visitHistory = history;
        _status = '총 ${history.length}개의 방문 기록을 불러왔습니다.';
      });
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _status = '방문 기록 로딩 중 오류 발생: $e');
      print('Error loading history: $e');
      print('Stack trace: $s');
    }
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

    final body = utf8.decode(res.bodyBytes); // UTF-8로 디코딩
    final lines = const LineSplitter().convert(body);
    return lines
        .where((line) => line.trim().isNotEmpty) // 빈 줄 제외
        .map<Map<String, dynamic>>((l) {
          try {
            return jsonDecode(l) as Map<String, dynamic>;
          } catch (e) {
            print("JSONL 파싱 오류: '$l', 오류: $e");
            return {}; // 파싱 오류 시 빈 맵 반환 또는 오류 처리
          }
        })
        .where((item) => item.isNotEmpty) // 파싱 오류로 빈 맵이 된 경우 제외
        .toList();
  }

  void _handleSummarizeAction() async {
    if (_isSummarizing) return; // 이미 요약 중이면 중복 실행 방지

    if (_selectedTimestamps.length == 1) {
      final selectedTimestamp = _selectedTimestamps.first;
      String? selectedUrl;

      for (var item in _visitHistory) {
        final timestamp = item['timestamp'] ?? item['visitTime'];
        if (timestamp == selectedTimestamp) {
          selectedUrl = item['url'] as String?;
          break;
        }
      }

      if (selectedUrl != null && selectedUrl.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _isSummarizing = true; // 요약 시작 상태
          _bottomSectionKey.currentState?.updateSummary(
            'URL 요약 중...\n$selectedUrl',
          );
        });

        // ai_service.dart의 함수 호출로 변경
        final String? summary = await crawlAndSummarizeUrl(selectedUrl);

        if (!mounted) return; // 비동기 작업 후 위젯 상태 확인
        _bottomSectionKey.currentState?.updateSummary(
          summary ?? '요약에 실패했거나 내용이 없습니다.',
        );
        setState(() {
          _isSummarizing = false; // 요약 완료 상태
        });

        if (summary == null ||
            summary.contains("오류") ||
            summary.contains("실패")) {
          print('❌ 요약 실패 또는 오류: $summary');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(summary ?? 'URL 요약에 실패했습니다.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('유효한 URL을 찾을 수 없습니다.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedTimestamps.isEmpty
                ? '내용을 요약할 URL을 선택해주세요.'
                : '내용을 요약할 URL은 하나만 선택할 수 있습니다.',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 방문 기록을 날짜별로 그룹화
    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var item in _visitHistory) {
      final timestamp = item['timestamp'] ?? item['visitTime']?.toString();
      if (timestamp == null || timestamp.length < 10) continue;
      final date = timestamp.substring(0, 10);
      groupedByDate.putIfAbsent(date, () => []).add(item);
    }

    // 날짜 최신순으로 정렬
    final sortedDates =
        groupedByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return LeftSidebarLayout(
      activePage: PageType.history, // PageType은 정의된 enum 값 사용
      child: Column(
        children: [
          Container(
            height: 40,
            color: Colors.grey[300],
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              '방문 기록',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child:
                _status.contains('불러오는 중...') && _visitHistory.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text(_status),
                        ],
                      ),
                    )
                    : _visitHistory.isEmpty
                    ? Center(child: Text(_status)) // '파일 없음' 또는 '오류' 메시지
                    : ListView.builder(
                      itemCount: sortedDates.length,
                      itemBuilder: (context, index) {
                        final date = sortedDates[index];
                        final itemsOnDate =
                            groupedByDate[date]!..sort((a, b) {
                              // 날짜 내에서는 시간 역순으로 정렬
                              final at =
                                  a['timestamp'] ?? a['visitTime']?.toString();
                              final bt =
                                  b['timestamp'] ?? b['visitTime']?.toString();
                              if (at == null && bt == null) return 0;
                              if (at == null) return 1; // null을 뒤로
                              if (bt == null) return -1; // null을 뒤로
                              return bt.compareTo(at);
                            });

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8.0,
                            horizontal: 12.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatDateKorean(date),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(height: 0),
                              ...itemsOnDate.map((item) {
                                final title =
                                    item['title']?.toString() ??
                                    item['url']?.toString() ??
                                    '제목 없음';
                                final url = item['url']?.toString() ?? '';
                                final timestamp =
                                    item['timestamp'] ??
                                    item['visitTime']?.toString();
                                final time = _formatTime(timestamp);
                                final bool isChecked = _selectedTimestamps
                                    .contains(timestamp);
                                return ListTile(
                                  leading: Padding(
                                    padding: EdgeInsets.zero, // 원하는 여백 설정
                                    child: Transform.scale(
                                      scale: 0.9, // 크기 축소
                                      child: Checkbox(
                                        value: isChecked,
                                        activeColor: Colors.deepPurple,
                                        visualDensity: VisualDensity.compact,
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
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  subtitle: Align(
                                    alignment: Alignment.centerLeft,
                                    child: RichText(
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      text: TextSpan(
                                        text: url,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue, // 테마 색상 사용
                                          decoration:
                                              TextDecoration
                                                  .none, // 밑줄 제거는 onTap으로
                                        ),
                                        recognizer:
                                            TapGestureRecognizer()
                                              ..onTap = () async {
                                                if (url.isNotEmpty) {
                                                  final uri = Uri.tryParse(url);
                                                  if (uri != null &&
                                                      await canLaunchUrl(uri)) {
                                                    await launchUrl(
                                                      uri,
                                                      mode:
                                                          LaunchMode
                                                              .externalApplication,
                                                    );
                                                  } else {
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
                                              },
                                      ),
                                    ),
                                  ),
                                  trailing: Text(
                                    time,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 0,
                                    vertical: 0,
                                  ), // 내부 패딩 조절
                                );
                              }).toList(),
                              if (index < sortedDates.length - 1)
                                const Divider(height: 20),
                            ],
                          ),
                        );
                      },
                    ),
          ),
          CollapsibleBottomSection(
            key: _bottomSectionKey,
            onSummarizePressed:
                _isSummarizing
                    ? null
                    : _handleSummarizeAction, // 요약 중일 때 버튼 비활성화
            isLoading: _isSummarizing, // 로딩 상태 전달
          ),
        ],
      ),
    );
  }

  String _formatDateKorean(String yyyyMMdd) {
    try {
      final date = DateTime.parse(yyyyMMdd);
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      return '${date.year}년 ${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
    } catch (_) {
      return yyyyMMdd; // 파싱 실패 시 원본 반환
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dateTime = DateTime.parse(isoString).toLocal(); // 로컬 시간대로 변환
      final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final ampm =
          dateTime.hour < 12 || dateTime.hour == 24
              ? '오전'
              : '오후'; // 24시(자정)도 오전으로
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$ampm $hour12:$minute';
    } catch (_) {
      // ISO 문자열이 아닌 다른 형식의 시간 정보일 수 있음 (예: HH:mm:ss)
      // 간단히 원본 반환하거나, 추가적인 시간 포맷 파싱 로직 필요
      return isoString.length > 5
          ? isoString.substring(isoString.length - 8, isoString.length - 3)
          : isoString;
    }
  }
}

// CollapsibleBottomSection 위젯과 LeftSidebarLayout 위젯, PageType enum의 정의가 필요합니다.
// 예시:
// enum PageType { home, history, settings }
// class CollapsibleBottomSectionState extends State<CollapsibleBottomSection> {
//   void updateSummary(String summary) { /* ... */ }
//   @override
//   Widget build(BuildContext context) { return Container(); }
// }
// class CollapsibleBottomSection extends StatefulWidget {
//   final GlobalKey<CollapsibleBottomSectionState>? key;
//   final VoidCallback? onSummarizePressed;
//   final bool isLoading;
//   const CollapsibleBottomSection({this.key, this.onSummarizePressed, this.isLoading = false}) : super(key: key);
//   @override
//   CollapsibleBottomSectionState createState() => CollapsibleBottomSectionState();
// }
