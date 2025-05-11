// 필요한 라이브러리 및 내부 파일 import
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // 외부 링크 열기 위한 패키지 추가
import '../layout/left_sidebar_layout.dart';
import '../layout/bottom_section.dart';
import '../services/google_drive_auth.dart';

// 방문 기록 페이지를 상태를 가지는 위젯으로 정의
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

// 상태 클래스 정의
class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _visitHistory = []; // 방문 기록 리스트
  final Set<String> _selectedTimestamps = {}; // 체크된 항목을 저장할 Set
  String _status = '불러오는 중...'; // 상태 메시지
  final folderId = '18gvXku0NzRbFrWJtsuI52dX0IJq_IE1f'; // Google Drive 폴더 ID

  @override
  void initState() {
    super.initState();
    _loadVisitHistory(); // 초기 데이터 불러오기
  }

  // 방문 기록을 Google Drive에서 불러오는 함수
  Future<void> _loadVisitHistory() async {
    final auth = GoogleDriveAuth();
    await auth.logout(); // 로그인 오류 시 주석 제거 후 핫로드
    print("저장된 토큰 강제 삭제 완료 (테스트 목적)");

    final token = await auth.getAccessToken();
    if (token == null) {
      setState(() => _status = 'Google 로그인 실패');
      return;
    }

    try {
      // 가장 최신의 jsonl 파일 ID 가져오기
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&pageSize=1'
      );
      final res = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
      });

      final data = jsonDecode(res.body);
      if ((data['files'] as List).isEmpty) {
        setState(() => _status = '방문기록 파일을 찾을 수 없음');
        return;
      }

      final fileId = data['files'][0]['id'];
      final history = await _downloadAndParseJsonl(token, fileId);

      setState(() {
        _visitHistory = history;
        _status = '총 ${history.length}개 기록 불러옴';
      });
    } catch (e) {
      setState(() => _status = '오류 발생: $e');
    }
  }

  // jsonl 파일 다운로드 및 파싱 함수
  Future<List<Map<String, dynamic>>> _downloadAndParseJsonl(String token, String fileId) async {
    final url = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final res = await http.get(url, headers: {'Authorization': 'Bearer $token'});
    final body = utf8.decode(res.bodyBytes); // UTF-8 디코딩으로 한글 깨짐 방지
    final lines = const LineSplitter().convert(body);
    return lines.map<Map<String, dynamic>>((l) => jsonDecode(l) as Map<String, dynamic>).toList();
  }

  @override
  Widget build(BuildContext context) {
    // 날짜별로 방문 기록을 그룹화
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in _visitHistory) {
      final timestamp = item['timestamp'] ?? item['visitTime'];
      final date = timestamp?.toString().substring(0, 10);
      if (date == null) continue;
      grouped.putIfAbsent(date, () => []).add(item);
    }

    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return LeftSidebarLayout(
      activePage: PageType.history,
      child: Column(
        children: [
          // 상단 제목 바
          Container(
            height: 50,
            color: Colors.grey[300],
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              '방문 기록',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          // 기록 리스트 표시 영역
          Expanded(
            child: _visitHistory.isEmpty
                ? Center(child: Text(_status))
                : ListView.builder(
                    itemCount: sortedDates.length,
                    itemBuilder: (context, index) {
                      final date = sortedDates[index];
                      final items = grouped[date]!..sort((a, b) {
                        final at = a['timestamp'] ?? a['visitTime'];
                        final bt = b['timestamp'] ?? b['visitTime'];
                        return bt.compareTo(at);
                      });

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 날짜 헤더
                            Text(
                              _formatDateKorean(date),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // 각 기록 항목
                            ...items.map((item) {
                              final title = item['title'] ?? item['url'] ?? '';
                              final url = item['url'] ?? '';
                              final timestamp = item['timestamp'] ?? item['visitTime'];
                              final time = _formatTime(timestamp);
                              final isChecked = _selectedTimestamps.contains(timestamp);
                              return ListTile(
                                leading: Checkbox(
                                  value: isChecked,
                                  onChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedTimestamps.add(timestamp);
                                      } else {
                                        _selectedTimestamps.remove(timestamp);
                                      }
                                    });
                                  },
                                ),
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // ✅ 하이퍼링크를 한 줄로 표시하고 말줄임 적용
                                subtitle: Align(
                                  alignment: Alignment.centerLeft,
                                  child: RichText(
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    text: TextSpan(
                                      text: url,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF0C64E8),
                                        decoration: TextDecoration.none,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () async {
                                          final uri = Uri.tryParse(url);
                                          if (uri != null && await canLaunchUrl(uri)) {
                                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                                          }
                                        },
                                    ),
                                  ),
                                ),
                                trailing: Text(time, style: const TextStyle(fontSize: 12)),
                              );
                            }),
                            const Divider(),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const CollapsibleBottomSection(), // 하단 영역
        ],
      ),
    );
  }

  // 날짜를 한국식 포맷으로 변환 (예: 2025.05.13 (화))
  String _formatDateKorean(String yyyyMMdd) {
    try {
      final date = DateTime.parse(yyyyMMdd);
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      return '${date.year}. ${date.month.toString().padLeft(2, '0')}. ${date.day.toString().padLeft(2, '0')} (${weekdays[date.weekday - 1]})';
    } catch (_) {
      return yyyyMMdd;
    }
  }

  // 시간 문자열을 오전/오후 형식으로 변환
  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final time = DateTime.parse(isoString).toLocal();
      final hour = time.hour > 12 ? '오후 ${time.hour - 12}' : '오전 ${time.hour}';
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }
}
