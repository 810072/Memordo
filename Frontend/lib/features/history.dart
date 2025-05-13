// lib/features/history.dart

import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../layout/left_sidebar_layout.dart';
import '../layout/bottom_section.dart';
import '../services/google_drive_auth.dart';
import '../utils/web_crawler.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _visitHistory = [];
  final Set<String> _selectedTimestamps = {};
  String _status = '불러오는 중...';
  final folderId = '18gvXku0NzRbFrWJtsuI52dX0IJq_IE1f';
  final GlobalKey<CollapsibleBottomSectionState> _bottomSectionKey =
      GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadVisitHistory();
  }

  Future<void> _loadVisitHistory() async {
    final auth = GoogleDriveAuth();
    // await auth.logout();
    final token = await auth.getAccessToken();
    if (token == null) {
      setState(() => _status = 'Google 로그인 실패');
      return;
    }

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&pageSize=1',
      );
      final res = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

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
    final body = utf8.decode(res.bodyBytes);
    final lines = const LineSplitter().convert(body);
    return lines
        .map<Map<String, dynamic>>((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
  }

  void _handleSummarizeAction() async {
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
        final summary = await crawlSaveAndSummarize(selectedUrl);

        if (summary != null) {
          _bottomSectionKey.currentState?.updateSummary(summary);
        } else {
          print('❌ 요약 실패');
        }
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
            child:
                _visitHistory.isEmpty
                    ? Center(child: Text(_status))
                    : ListView.builder(
                      itemCount: sortedDates.length,
                      itemBuilder: (context, index) {
                        final date = sortedDates[index];
                        final items =
                            grouped[date]!..sort((a, b) {
                              final at = a['timestamp'] ?? a['visitTime'];
                              final bt = b['timestamp'] ?? b['visitTime'];
                              return bt.compareTo(at);
                            });

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
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
                                final title =
                                    item['title'] ?? item['url'] ?? '';
                                final url = item['url'] ?? '';
                                final timestamp =
                                    item['timestamp'] ?? item['visitTime'];
                                final time = _formatTime(timestamp);
                                final isChecked = _selectedTimestamps.contains(
                                  timestamp,
                                );

                                return ListTile(
                                  leading: Checkbox(
                                    value: isChecked,
                                    activeColor: Colors.deepPurple,
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
                                        recognizer:
                                            TapGestureRecognizer()
                                              ..onTap = () async {
                                                final uri = Uri.tryParse(url);
                                                if (uri != null &&
                                                    await canLaunchUrl(uri)) {
                                                  await launchUrl(
                                                    uri,
                                                    mode:
                                                        LaunchMode
                                                            .externalApplication,
                                                  );
                                                }
                                              },
                                      ),
                                    ),
                                  ),
                                  trailing: Text(
                                    time,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              }),
                              const Divider(),
                            ],
                          ),
                        );
                      },
                    ),
          ),
          CollapsibleBottomSection(
            key: _bottomSectionKey,
            onSummarizePressed: _handleSummarizeAction,
          ),
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
      final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
      final ampm = time.hour < 12 || time.hour == 24 ? '오전' : '오후';
      final minute = time.minute.toString().padLeft(2, '0');
      return '$ampm $hour12:$minute';
    } catch (_) {
      return '';
    }
  }
}
