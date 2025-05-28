// lib/features/history.dart
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart'; // Provider 임포트
import '../layout/left_sidebar_layout.dart';
import '../layout/bottom_section.dart';
import '../utils/ai_service.dart';
import '../layout/bottom_section_controller.dart'; // 컨트롤러 임포트
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/auth_token.dart'; // accessToken 관련 함수
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 구글 토큰 갱신 시 필요
import '../auth/login_page.dart';
import 'dart:io'; // ✅ HttpServer, HttpRequest, InternetAddress, ContentType 제공
import '../services/auth_token.dart'; // JWT 저장용

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

  @override
  void initState() {
    super.initState();
    // _loadVisitHistory();
    _checkTokensThenLoad();
  }

  Future<void> _checkTokensThenLoad() async {
    final accessToken = await getStoredAccessToken();
    final googleAccessToken = await getStoredGoogleAccessToken();
    final googleRefreshToken = await getStoredGoogleRefreshToken();

    // 자체 토큰 확인
    if (accessToken == null || accessToken.isEmpty) {
      print('❗ accessToken 없음 → refresh 시도');

      try {
        await refreshAccessTokenIfNeeded(); // 🔄 access token 재발급
        final newToken = await getStoredAccessToken();

        if (newToken == null || newToken.isEmpty) {
          throw Exception('accessToken 재발급 실패');
        }
        print('✅ accessToken 재발급 성공');
      } catch (e) {
        print('❌ accessToken 재발급 실패: $e');
        _navigateToLogin();
        return;
      }
    }

    // 구글 토큰 확인
    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      print('❗ Google accessToken 없음');

      if (googleRefreshToken == null || googleRefreshToken.isEmpty) {
        print('❌ Google refreshToken 없음 → 로그인 필요');
        _signInWithGoogle();
        return;
      }

      try {
        await refreshGoogleAccessTokenIfNeeded(); // 🔄 구글 access token 재발급
        final refreshed = await getStoredGoogleAccessToken();

        if (refreshed == null || refreshed.isEmpty) {
          throw Exception('Google accessToken 재발급 실패');
        }
        print('✅ Google accessToken 재발급 성공');
      } catch (e) {
        print('❌ Google accessToken 갱신 실패: $e');
        _signInWithGoogle();
        return;
      }
    }
    _loadVisitHistory(); // ✅ accessToken 또는 googleAccessToken 준비됨
  }

  //구글 파일 히스토리 가져오기
  Future<void> _loadVisitHistory() async {
    setState(() => _status = '방문 기록 불러오는 중...');
    print("_loadVisitHistory !!!!!!");
    // final auth = GoogleDriveAuth();

    final googleAccessToken = await getStoredGoogleAccessToken();

    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      setState(() => _status = 'Google 인증 실패');
      return;
    }

    const folderName = 'memordo';
    final folderId = await _getFolderIdByName(folderName, googleAccessToken);
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

    setState(() {
      _visitHistory = history;
      _status = '총 ${history.length}개의 방문 기록을 불러왔습니다.';
    });
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  //구글 로그인
  Future<void> _signInWithGoogle() async {
    final clientId = dotenv.env['GOOGLE_CLIENT_ID_WEB'];
    final redirectUri = dotenv.env['REDIRECT_URI'];

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'response_type': 'code',
      'client_id': clientId!,
      'redirect_uri': redirectUri!,
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

      // ✅ 코드 값 확인 및 로깅
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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final accessToken = data['accessToken'];
        final refreshToken = data['refreshToken'];
        final googleAccessToken = data['googleAccessToken'];
        final googleRefreshToken = data['googleRefreshToken'];

        if (accessToken != null) {
          await setStoredAccessToken(accessToken);
          print('✅ accessToken 저장 완료: $accessToken');
        }
        if (refreshToken != null) {
          await setStoredRefreshToken(refreshToken);
          print('✅ refreshToken 저장 완료: $refreshToken');
        }
        if (googleAccessToken != null) {
          await setStoredGoogleAccessToken(googleAccessToken);
          print('✅ googleAccessToken 저장 완료: $googleAccessToken');
        }
        if (googleRefreshToken != null) {
          await setStoredGoogleRefreshToken(googleRefreshToken);
          print('✅ googleRefreshToken 저장 완료: $googleRefreshToken');
        }
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        print('❌ 서버 인증 실패: ${response.statusCode}, ${response.body}');
        _showSnackBar('Google 로그인 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('에러 코드 : ${e}');
      print('⚠️ Google 로그인 오류: $e');
      _showSnackBar('Google 로그인 중 오류 발생');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  //구글 로그인 인증 (웹페이지부분) -> 인증 완료시 페이지
  Future<String?> _waitForCode(String redirectUri) async {
    final int port = Uri.parse(redirectUri).port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    print('✅ 서버가 인증 코드를 기다리는 중입니다. (http://localhost:$port)');

    final HttpRequest request = await server.first;
    final Uri uri = request.uri;
    final String? code = uri.queryParameters['code'];

    // 응답 보내기
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write('''
      <html>
        <head><title>로그인 완료</title></head>
        <body>
          <h2>✅ 로그인 처리가 완료되었습니다.</h2>
          <p>이 창을 닫아주세요.</p>
        </body>
      </html>
    ''');
    await request.response.close();
    await server.close();

    if (code == null) {
      print('❌ 인증 코드가 전달되지 않았습니다.');
    } else {
      print('✅ 인증 코드 수신 완료: $code');
    }

    return code;
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

  void _handleSummarizeAction() async {
    // BottomSectionController 인스턴스 가져오기
    final bottomController = Provider.of<BottomSectionController>(
      context,
      listen: false,
    );

    if (bottomController.isLoading) return; // 이미 요약 중이면 중복 실행 방지

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

        bottomController.setIsLoading(true); // 로딩 상태 시작
        bottomController.updateSummary(
          '',
        ); // 기존 요약 내용 초기화 (CollapsibleBottomSection이 '요약 중...' 표시)
        bottomController.updateSummary(
          'URL 요약 중...\n$selectedUrl',
        ); // URL 요약 중 메시지 표시

        final String? summary = await crawlAndSummarizeUrl(selectedUrl);

        if (!mounted) return; // 비동기 작업 후 위젯 상태 확인
        bottomController.updateSummary(summary ?? '요약에 실패했거나 내용이 없습니다.');
        bottomController.setIsLoading(false); // 로딩 상태 종료

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

    // BottomSectionController 인스턴스 가져오기 (listen: true로 변화 감지)
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
            // 로딩 상태는 이제 BottomSectionController에서 관리됩니다.
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
}
