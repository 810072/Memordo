// Frontend/lib/features/history.dart
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../widgets/ai_summary_widget.dart';
import '../utils/ai_service.dart';
import '../services/auth_token.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../auth/login_page.dart';
import '../layout/bottom_section_controller.dart';
import '../features/meeting_screen.dart';

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

  Future<void> _checkTokensThenLoad() async {
    final accessToken = await getStoredAccessToken();
    final googleAccessToken = await getStoredGoogleAccessToken();
    final googleRefreshToken = await getStoredGoogleRefreshToken();

    if (accessToken == null || accessToken.isEmpty) {
      try {
        await refreshAccessTokenIfNeeded();
        final newToken = await getStoredAccessToken();
        if (newToken == null || newToken.isEmpty) {
          throw Exception('accessToken 재발급 실패');
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginPage()),
        );
        return;
      }
    }

    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      if (googleRefreshToken == null || googleRefreshToken.isEmpty) {
        await _signInWithGoogle();
        return;
      }

      try {
        await refreshGoogleAccessTokenIfNeeded();
        final refreshed = await getStoredGoogleAccessToken();
        if (!mounted) return;
        if (refreshed == null || refreshed.isEmpty) {
          throw Exception('Google accessToken 재발급 실패');
        }
      } catch (e) {
        await _signInWithGoogle();
        return;
      }
    }
    if (!mounted) return;
    _loadVisitHistory();
  }

  Future<String?> getValidGoogleAccessToken() async {
    var googleAccessToken = await getStoredGoogleAccessToken();

    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      await refreshGoogleAccessTokenIfNeeded();
      googleAccessToken = await getStoredGoogleAccessToken();
    }

    return googleAccessToken;
  }

  Future<void> _loadVisitHistory() async {
    if (!mounted) return;
    setState(() => _status = '방문 기록 불러오는 중...');
    final googleAccessToken = await getValidGoogleAccessToken();

    if (!mounted) return;

    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      setState(() => _status = 'Google 인증 실패');
      return;
    }

    const folderName = 'memordo';
    final folderId = await _getFolderIdByName(folderName, googleAccessToken);
    if (!mounted) return;

    if (folderId == null) {
      setState(() => _status = 'memordo 폴더를 찾을 수 없습니다.');
      return;
    }

    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&pageSize=10',
    );

    final res = await http.get(
      url,
      headers: {'Authorization': 'Bearer $googleAccessToken'},
    );
    if (!mounted) return;

    if (res.statusCode != 200) {
      setState(() => _status = '파일 목록 조회 실패 (${res.statusCode})');
      return;
    }

    final data = jsonDecode(res.body);
    final files = data['files'] as List;
    if (files.isEmpty) {
      setState(() => _status = 'jsonl 파일이 없습니다.');
      return;
    }

    final fileId = files[0]['id'];
    final history = await _downloadAndParseJsonl(googleAccessToken, fileId);
    if (!mounted) return;

    setState(() {
      _visitHistory = history;
      _status =
          history.isEmpty
              ? '방문 기록이 없습니다.'
              : '총 ${history.length}개의 방문 기록을 불러왔습니다.';
    });
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

      if (files.isNotEmpty) {
        return files[0]['id'] as String;
      } else {
        return null;
      }
    } else {
      return null;
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

  Future<void> _signInWithGoogle() async {
    final clientId = dotenv.env['GOOGLE_CLIENT_ID_WEB'];
    final redirectUri = dotenv.env['REDIRECT_URI'];

    if (clientId == null || redirectUri == null) {
      _showSnackBar('Google 로그인 설정 오류');
      return;
    }

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope':
          'openid email profile https://www.googleapis.com/auth/drive.readonly',
      'access_type': 'offline',
      'prompt': 'consent',
    });

    try {
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      } else {
        throw '브라우저 열기 실패: $authUrl';
      }

      final code = await _waitForCode(redirectUri);
      if (!mounted) return;

      if (code == null || code.isEmpty) {
        _showSnackBar('Google 로그인 실패: code가 비어 있습니다.');
        return;
      }

      final response = await http.post(
        Uri.parse('$baseUrl$apiPrefix/google-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final accessToken = data['accessToken'];
        final refreshToken = data['refreshToken'];
        final googleAccessToken = data['googleAccessToken'];
        final googleRefreshToken = data['googleRefreshToken'];

        if (accessToken != null) await setStoredAccessToken(accessToken);
        if (refreshToken != null) await setStoredRefreshToken(refreshToken);
        if (googleAccessToken != null)
          await setStoredGoogleAccessToken(googleAccessToken);
        if (googleRefreshToken != null)
          await setStoredGoogleRefreshToken(googleRefreshToken);

        _checkTokensThenLoad();
      } else {
        _showSnackBar('Google 로그인 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Google 로그인 중 오류 발생: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _waitForCode(String redirectUriString) async {
    final Uri redirectUri = Uri.parse(redirectUriString);
    final int port = redirectUri.port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);

    try {
      final HttpRequest request = await server.first.timeout(
        const Duration(minutes: 2),
      );
      final Uri uri = request.uri;
      final String? code = uri.queryParameters['code'];
      final String? error = uri.queryParameters['error'];

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html;

      if (error != null) {
        request.response.write('''
            <html><head><title>로그인 오류</title></head>
            <body><h2>❌ 로그인 중 오류가 발생했습니다.</h2><p>오류: $error</p><p>이 창을 닫고 앱으로 돌아가세요.</p></body></html>
            ''');
      } else if (code != null) {
        request.response.write('''
            <html><head><title>로그인 완료</title></head>
            <body><h2>✅ 로그인 처리가 완료되었습니다.</h2><p>이 창을 닫고 앱으로 돌아가세요.</p></body></html>
            ''');
      } else {
        request.response.write('''
            <html><head><title>로그인 실패</title></head>
            <body><h2>❌ 로그인에 실패했습니다 (코드를 받지 못함).</h2><p>이 창을 닫고 앱으로 돌아가세요.</p></body></html>
            ''');
      }
      await request.response.close();
      return code;
    } catch (e) {
      return null;
    } finally {
      await server.close();
    }
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
        setState(() {
          _showSummary = true;
        });

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(summary ?? 'URL 요약에 실패했습니다.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('유효한 URL을 찾을 수 없습니다.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    } else {
      if (!mounted) return;
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

  void _createNewMemoWithSummary() {
    final bottomController = Provider.of<BottomSectionController>(
      context,
      listen: false,
    );
    final summary = bottomController.summaryText;

    if (summary.isNotEmpty &&
        summary != 'AI가 요약 중입니다...' &&
        !summary.contains('요약에 실패') &&
        !summary.contains('오류') &&
        !summary.contains('내용이 없습니다')) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MeetingScreen(initialText: summary),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('생성할 요약 내용이 없습니다.'),
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

    return Column(
      children: [
        Container(
          // ✨ [수정] height를 45로 변경
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).appBarTheme.backgroundColor,
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
                onPressed: _handleSummarizeAction,
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
            children: [
              Expanded(
                flex: _showSummary ? 2 : 3,
                child: Container(
                  margin: const EdgeInsets.all(16.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child:
                      _visitHistory.isEmpty
                          ? Center(child: Text(_status))
                          : ListView.builder(
                            itemCount: sortedDates.length,
                            itemBuilder: (context, index) {
                              final date = sortedDates[index];
                              final itemsOnDate =
                                  groupedByDate[date]!..sort((a, b) {
                                    final at =
                                        a['timestamp'] ??
                                        a['visitTime']?.toString();
                                    final bt =
                                        b['timestamp'] ??
                                        b['visitTime']?.toString();
                                    if (at == null && bt == null) return 0;
                                    if (at == null) return 1;
                                    if (bt == null) return -1;
                                    return bt.compareTo(at);
                                  });

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 0.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                        vertical: 0.0,
                                      ),
                                      child: Text(
                                        _formatDateKorean(date),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                    ),
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

                                      return Card(
                                        elevation: 1.0,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 0.0,
                                          horizontal: 8.0,
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
                                          leading: Transform.scale(
                                            scale: 0.8,
                                            child: Checkbox(
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
                                          ),
                                          title: Text(
                                            title,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
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
                                                                .shade700,
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
                                                                  if (!mounted)
                                                                    return;
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
                                                vertical: 0.0,
                                              ),
                                          dense: true,
                                          minVerticalPadding: 0.0,
                                          onTap: () {
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
              if (_showSummary)
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(
                          top: 16.0,
                          right: 16.0,
                          bottom: 8.0,
                        ),
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 1,
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: AiSummaryWidget(),
                      ),
                      if (!bottomController.isLoading &&
                          bottomController.summaryText.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(
                            right: 16.0,
                            bottom: 16.0,
                          ),
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.note_add_outlined, size: 18),
                            label: const Text("새 메모 작성"),
                            onPressed: _createNewMemoWithSummary,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF27ae60),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
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
      DateTime dateTime = DateTime.parse(isoString);
      if (!dateTime.isUtc) {}
      dateTime = dateTime.toLocal();

      final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final ampm = dateTime.hour < 12 ? '오전' : '오후';
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$ampm $hour12:$minute';
    } catch (_) {
      if (isoString.contains("T")) {
        final parts = isoString.split("T");
        if (parts.length > 1 && parts[1].length >= 5) {
          return parts[1].substring(0, 5);
        }
      }
      return isoString.length > 15 ? isoString.substring(11, 16) : isoString;
    }
  }
}
