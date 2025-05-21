// lib/features/history.dart
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../layout/left_sidebar_layout.dart';
import '../layout/bottom_section.dart';
import '../services/google_drive_platform.dart';
import '../utils/ai_service.dart';
import '../layout/bottom_section_controller.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _visitHistory = [];
  final Set<String> _selectedTimestamps = {};
  String _status = '불러오는 중...';

  @override
  void initState() {
    super.initState();
    _loadVisitHistory();
  }

  Future<String?> _getFolderIdByName(String folderName, String token) async {
    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=mimeType=%27application/vnd.google-apps.folder%27+and+name=%27$folderName%27&fields=files(id,name)&pageSize=1',
    );
    final res = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final files = data['files'] as List;
      if (files.isNotEmpty) {
        return files[0]['id'];
      }
    } else {
      print('폴더 ID 조회 실패 (상태: ${res.statusCode}): ${res.body}');
    }
    return null;
  }

  Future<void> _loadVisitHistory() async {
    if (!mounted) return;
    setState(() => _status = '방문 기록 불러오는 중...');
    final auth = GoogleDriveAuth();
    final token = await auth.getAccessToken();

    if (token == null) {
      setState(() => _status = 'Google 로그인에 실패했습니다. 다시 시도해주세요.');
      return;
    }

    try {
      const folderName = 'memordo'; // 변경 가능한 폴더 이름
      final folderId = await _getFolderIdByName(folderName, token);

      if (folderId == null) {
        setState(() => _status = '폴더 "$folderName"을(를) 찾을 수 없습니다.');
        return;
      }

      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&pageSize=10',
      );
      final res = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        await auth.logout();
        setState(
          () => _status = 'Google Drive 파일 목록 가져오기 실패 (상태: ${res.statusCode})',
        );
        print('Drive API Error: ${res.body}');
        return;
      }

      final data = jsonDecode(res.body);
      if ((data['files'] as List).isEmpty) {
        setState(() => _status = '방문기록(.jsonl) 파일을 찾을 수 없습니다.');
        return;
      }

      final fileId = data['files'][0]['id'];
      final history = await _downloadAndParseJsonl(token, fileId);

      setState(() {
        _visitHistory = history;
        _status = '총 ${history.length}개의 방문 기록을 불러왔습니다.';
      });
    } catch (e, s) {
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

    final body = utf8.decode(res.bodyBytes);
    final lines = const LineSplitter().convert(body);
    return lines
        .where((line) => line.trim().isNotEmpty)
        .map<Map<String, dynamic>>((l) {
          try {
            return jsonDecode(l) as Map<String, dynamic>;
          } catch (e) {
            print("JSONL 파싱 오류: '$l', 오류: $e");
            return {};
          }
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _handleSummarizeAction() async {
    final bottomController = Provider.of<BottomSectionController>(
      context,
      listen: false,
    );

    if (bottomController.isLoading) return;

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

        bottomController.setIsLoading(true);
        bottomController.updateSummary('');
        bottomController.updateSummary('URL 요약 중...\n$selectedUrl');

        final String? summary = await crawlAndSummarizeUrl(selectedUrl);

        if (!mounted) return;
        bottomController.updateSummary(summary ?? '요약에 실패했거나 내용이 없습니다.');
        bottomController.setIsLoading(false);

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
    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var item in _visitHistory) {
      final timestamp = item['timestamp'] ?? item['visitTime']?.toString();
      if (timestamp == null || timestamp.length < 10) continue;
      final date = timestamp.substring(0, 10);
      groupedByDate.putIfAbsent(date, () => []).add(item);
    }

    final sortedDates =
        groupedByDate.keys.toList()..sort((a, b) => b.compareTo(a));
    final bottomController = Provider.of<BottomSectionController>(context);

    return LeftSidebarLayout(
      activePage: PageType.history,
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
                    ? Center(child: Text(_status))
                    : ListView.builder(
                      itemCount: sortedDates.length,
                      itemBuilder: (context, index) {
                        final date = sortedDates[index];
                        final itemsOnDate =
                            groupedByDate[date]!..sort((a, b) {
                              final at =
                                  a['timestamp'] ?? a['visitTime']?.toString();
                              final bt =
                                  b['timestamp'] ?? b['visitTime']?.toString();
                              if (at == null && bt == null) return 0;
                              if (at == null) return 1;
                              if (bt == null) return -1;
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
                                    padding: EdgeInsets.zero,
                                    child: Transform.scale(
                                      scale: 0.9,
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
                                          color: Colors.blue,
                                          decoration: TextDecoration.none,
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
                                  ),
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
            onSummarizePressed:
                bottomController.isLoading ? null : _handleSummarizeAction,
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
      return yyyyMMdd;
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final ampm = dateTime.hour < 12 || dateTime.hour == 24 ? '오전' : '오후';
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$ampm $hour12:$minute';
    } catch (_) {
      return isoString.length > 5
          ? isoString.substring(isoString.length - 8, isoString.length - 3)
          : isoString;
    }
  }
}
