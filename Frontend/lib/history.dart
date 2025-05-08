import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'google_drive_auth.dart';
import 'left_sidebar_layout.dart';
import 'bottom_section.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _visitHistory = [];
  String _status = '불러오는 중...';

  final folderId = '18gvXku0NzRbFrWJtsuI52dX0IJq_IE1f';

  @override
  void initState() {
    super.initState();
    _loadVisitHistory();
  }

  Future<void> _loadVisitHistory() async {
    final auth = GoogleDriveAuth();
    await auth.logout(); // ★★★ 테스트를 위해 임시로 로그아웃 호출하여 저장된 토큰 삭제 ★★★
    print("저장된 토큰 강제 삭제 완료 (테스트 목적)"); 
    final token = await auth.getAccessToken();

    if (token == null) {
      setState(() => _status = 'Google 로그인 실패');
      return;
    }

    try {
      final fileId = await _getLatestFileId(token);
      if (fileId == null) {
        setState(() => _status = '방문기록 파일을 찾을 수 없음');
        return;
      }

      final history = await _downloadAndParseJsonl(token, fileId);
      setState(() {
        _visitHistory = history;
        _status = '총 ${history.length}개 기록 불러옴';
      });
    } catch (e) {
      setState(() => _status = '오류 발생: $e');
    }
  }

  Future<String?> _getLatestFileId(String token) async {
    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=\'$folderId\'+in+parents+and+name+contains+\'.jsonl\'&orderBy=createdTime+desc&pageSize=1',
    );

    final res = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
    });

    final data = jsonDecode(res.body);
    if ((data['files'] as List).isEmpty) return null;

    return data['files'][0]['id'];
  }

  Future<List<Map<String, dynamic>>> _downloadAndParseJsonl(
      String token, String fileId) async {
    final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');

    final res = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
    });

    final lines = const LineSplitter().convert(res.body);
    return lines
        .map<Map<String, dynamic>>((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDateKorean(date),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...items.map((item) {
                              final url = item['url'] ?? '';
                              final time = _formatTime(item['timestamp'] ?? item['visitTime']);
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.link),
                                title: Text(url,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.blueAccent,
                                        overflow: TextOverflow.ellipsis)),
                                trailing: Text(time, style: const TextStyle(fontSize: 12)),
                                onTap: () {
                                  // 나중에 URL 클릭 기능 추가 가능
                                },
                              );
                            }),
                            const Divider(),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const CollapsibleBottomSection(),
        ],
      ),
    );
  }

  String _formatDateKorean(String yyyyMMdd) {
    try {
      final date = DateTime.parse(yyyyMMdd);
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      return '${date.year}. ${date.month.toString().padLeft(2, '0')}. ${date.day.toString().padLeft(2, '0')} (${weekdays[date.weekday - 1]})';
    } catch (_) {
      return yyyyMMdd;
    }
  }

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
