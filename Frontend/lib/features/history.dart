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
import '../layout/bottom_section_controller.dart';

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
  bool _showSummary = false; // Initially false

  @override
  void initState() {
    super.initState();
    _checkTokensThenLoad();
  }

  Future<void> _checkTokensThenLoad() async {
    final accessToken = await getStoredAccessToken();
    final googleAccessToken = await getStoredGoogleAccessToken();
    final googleRefreshToken = await getStoredGoogleRefreshToken();

    print("!!!!!!!! accessToken : $accessToken");
    print("!!!!!!!! googleAccessToken : $googleAccessToken");

    if (accessToken == null || accessToken.isEmpty) {
      print('❗ accessToken 없음 → refresh 시도');
      try {
        await refreshAccessTokenIfNeeded();
        final newToken = await getStoredAccessToken();
        if (newToken == null || newToken.isEmpty) {
          throw Exception('accessToken 재발급 실패');
        }
        print('✅ accessToken 재발급 성공');
      } catch (e) {
        print('❌ accessToken 재발급 실패: $e');
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginPage()),
        );
        return;
      }
    }

    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      print('❗ Google accessToken 없음');
      if (googleRefreshToken == null || googleRefreshToken.isEmpty) {
        print('❌ Google refreshToken 없음 → 로그인 필요');
        await _signInWithGoogle(); // This will handle navigation or further checks
        return; // Return as _signInWithGoogle might navigate
      }

      try {
        await refreshGoogleAccessTokenIfNeeded();
        final refreshed = await getStoredGoogleAccessToken();
        if (!mounted) return; // Check mounted after await
        if (refreshed == null || refreshed.isEmpty) {
          throw Exception('Google accessToken 재발급 실패');
        }
        print('✅ Google accessToken 재발급 성공');
      } catch (e) {
        print('❌ Google accessToken 갱신 실패: $e');
        await _signInWithGoogle(); // This will handle navigation or further checks
        return; // Return as _signInWithGoogle might navigate
      }
    }
    // If execution reaches here, all tokens should be fine or refreshed.
    // Check mounted again before loading history if there were awaits without immediate returns.
    if (!mounted) return;
    print('✅ 모든 토큰 정상 → 방문 기록 로드 시도');
    _loadVisitHistory();
  }

  Future<String?> getValidGoogleAccessToken() async {
    var googleAccessToken = await getStoredGoogleAccessToken();

    // 만료되었을 가능성 항상 체크
    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      await refreshGoogleAccessTokenIfNeeded();
      googleAccessToken = await getStoredGoogleAccessToken();
    }

    return googleAccessToken;
  }

  Future<void> _loadVisitHistory() async {
    if (!mounted) return;
    setState(() => _status = '방문 기록 불러오는 중...');
    print("_loadVisitHistory !!!!!!");
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
      print(res.body);
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
        print('폴더 "$folderName"를 찾을 수 없습니다.');
        return null;
      }
    } else {
      print('폴더 ID 조회 실패 (상태: ${res.statusCode}): ${res.body}');
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
            print('JSONL 파싱 실패: $line');
            return {};
          }
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _signInWithGoogle() async {
    final clientId = dotenv.env['GOOGLE_CLIENT_ID_WEB'];
    final redirectUri = dotenv.env['REDIRECT_URI'];

    if (clientId == null || redirectUri == null) {
      print('❌ Google Client ID 또는 Redirect URI가 .env 파일에 설정되지 않았습니다.');
      if (!mounted) return;
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
        print('❌ 받은 code가 null 또는 빈 값입니다.');
        return;
      }

      print('✅ 받은 Google 인증 code: $code');

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

        print('✅ 모든 토큰 저장 완료, 메인 화면으로 이동 또는 방문 기록 다시 로드');
        // Navigate to main or reload current page data
        // Navigator.pushReplacementNamed(context, '/main');
        _checkTokensThenLoad(); // Re-check tokens and load history
      } else {
        print('❌ 서버 인증 실패: ${response.statusCode}, ${response.body}');
        _showSnackBar('Google 로그인 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      print('에러 코드 : $e');
      print('⚠️ Google 로그인 오류: $e');
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
    // Ensure host is loopback for security if it's a localhost redirect
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    print('✅ 서버가 인증 코드를 기다리는 중입니다. (http://${server.address.host}:$port)');

    try {
      final HttpRequest request = await server.first.timeout(
        const Duration(minutes: 2),
      ); // Add timeout
      final Uri uri = request.uri;
      final String? code = uri.queryParameters['code'];
      final String? error = uri.queryParameters['error'];

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html;

      if (error != null) {
        print('❌ Google 로그인 오류 (OAuth): $error');
        request.response.write('''
            <html><head><title>로그인 오류</title></head>
            <body><h2>❌ 로그인 중 오류가 발생했습니다.</h2><p>오류: $error</p><p>이 창을 닫고 앱으로 돌아가세요.</p></body></html>
            ''');
      } else if (code != null) {
        print('✅ 인증 코드 수신 완료: $code');
        request.response.write('''
            <html><head><title>로그인 완료</title></head>
            <body><h2>✅ 로그인 처리가 완료되었습니다.</h2><p>이 창을 닫고 앱으로 돌아가세요.</p></body></html>
            ''');
      } else {
        print('❌ 인증 코드가 전달되지 않았습니다.');
        request.response.write('''
            <html><head><title>로그인 실패</title></head>
            <body><h2>❌ 로그인에 실패했습니다 (코드를 받지 못함).</h2><p>이 창을 닫고 앱으로 돌아가세요.</p></body></html>
            ''');
      }
      await request.response.close();
      return code; // Return null if error or no code
    } catch (e) {
      print('❌ _waitForCode 오류 또는 타임아웃: $e');
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
        // No await before these calls, so !mounted check isn't strictly needed here
        // but good practice if any async was to be introduced before.
        setState(() {
          _showSummary = true; // ✅ Show the summary widget area
        });

        bottomController.setIsLoading(true);
        bottomController.updateSummary(
          '', // Clear previous summary
        );
        bottomController.updateSummary('URL 요약 중...\n$selectedUrl');

        final String? summary = await crawlAndSummarizeUrl(selectedUrl);

        if (!mounted) return; // Crucial check after await

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

    return MainLayout(
      activePage: PageType.history,
      child: Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
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
                            ? Center(
                              child: Text(_status),
                            ) // Shows "불러오는 중..." or error/empty messages
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
                                    // Corrected padding here from original code
                                    vertical:
                                        0.0, // Reduced vertical padding for group
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        // Added padding for date header
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
                                      // const SizedBox(height: 8), // Original SizedBox
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
                                          elevation: 1.0,
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 0.0,
                                            horizontal: 8.0,
                                          ), // Added horizontal margin to card
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
                                              scale:
                                                  0.8, // ← 여기서 크기 조절 (0.8은 80% 크기)
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
                                                      _selectedTimestamps
                                                          .remove(timestamp);
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
                                                                        content:
                                                                            Text(
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
                                                  horizontal:
                                                      8.0, // ListTile padding
                                                  vertical:
                                                      0.0, // Reduced vertical padding for denser list
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
                                          height:
                                              30, // Increased height for visual separation
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
                if (_showSummary) // ✅ Conditionally display AiSummaryWidget
                  Expanded(
                    flex: 1,
                    child: Container(
                      margin: const EdgeInsets.only(
                        top: 16.0,
                        right: 16.0,
                        bottom: 16.0,
                        // left is implicitly handled by Expanded spacing or could be added: left: 8.0
                      ),
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12.0),
                        boxShadow: [
                          // Consistent shadow with the list view
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
                  ),
              ],
            ),
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
      return yyyyMMdd; // Fallback
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      // Ensure it's parsed as UTC if no timezone info, then convert to local.
      // If isoString already has Z or offset, parse will handle it.
      DateTime dateTime = DateTime.parse(isoString);
      if (!dateTime.isUtc) {
        // If parsed as local directly (e.g. no Z), ensure correct interpretation
        // This might not be needed if isoString is always proper ISO 8601 with TZ
      }
      dateTime = dateTime.toLocal(); // Convert to local time for display

      final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final ampm =
          dateTime.hour < 12 ? '오전' : '오후'; // Simpler AM/PM for 0-23 hours
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$ampm $hour12:$minute';
    } catch (_) {
      // Fallback for non-standard or partially valid time strings
      if (isoString.contains("T")) {
        final parts = isoString.split("T");
        if (parts.length > 1 && parts[1].length >= 5) {
          return parts[1].substring(0, 5); // HH:mm
        }
      }
      return isoString.length > 15
          ? isoString.substring(11, 16)
          : isoString; // Basic fallback
    }
  }
}
