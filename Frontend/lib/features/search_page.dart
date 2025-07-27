// lib/features/search_page.dart

import 'dart:convert';
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../services/auth_token.dart'; // 토큰 관련 함수
import '../auth/login_page.dart'; // 로그인 페이지로 이동 시 사용

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  List<Map<String, dynamic>> _visitHistory = []; // 원본 방문 기록
  List<Map<String, dynamic>> _filteredVisitHistory = []; // 검색 결과 방문 기록
  String _statusMessage = 'Google 방문 기록을 불러오는 중...';
  bool _isLoading = false;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadAndSearchHistory(); // 페이지 로드 시 방문 기록 불러오기
    _searchController.addListener(_onSearchChanged); // 검색어 변경 리스너
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _filterHistory(_searchController.text);
    });
  }

  void _filterHistory(String query) {
    final lowerCaseQuery = query.toLowerCase();
    setState(() {
      if (lowerCaseQuery.isEmpty) {
        _filteredVisitHistory = List.from(_visitHistory);
      } else {
        _filteredVisitHistory =
            _visitHistory.where((item) {
              final title = item['title']?.toString().toLowerCase() ?? '';
              final url = item['url']?.toString().toLowerCase() ?? '';
              return title.contains(lowerCaseQuery) ||
                  url.contains(lowerCaseQuery);
            }).toList();
      }
      _statusMessage =
          _filteredVisitHistory.isEmpty && lowerCaseQuery.isNotEmpty
              ? '검색 결과가 없습니다.'
              : '';
    });
  }

  Future<void> _loadAndSearchHistory() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Google 방문 기록을 불러오는 중...';
    });

    try {
      final accessToken = await getStoredAccessToken();
      final googleAccessToken = await getStoredGoogleAccessToken();
      final googleRefreshToken = await getStoredGoogleRefreshToken();

      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('메인 액세스 토큰 없음. 로그인 필요.');
      }

      if (googleAccessToken == null || googleAccessToken.isEmpty) {
        if (googleRefreshToken == null || googleRefreshToken.isEmpty) {
          throw Exception('Google 리프레시 토큰 없음. Google 로그인 필요.');
        }
        await refreshGoogleAccessTokenIfNeeded();
        final refreshedGoogleAccessToken = await getStoredGoogleAccessToken();
        if (refreshedGoogleAccessToken == null ||
            refreshedGoogleAccessToken.isEmpty) {
          throw Exception('Google 액세스 토큰 갱신 실패. Google 로그인 필요.');
        }
      }

      // Google Drive에서 방문 기록 파일 찾기 및 다운로드
      const folderName = 'memordo';
      final validGoogleAccessToken = await getValidGoogleAccessToken();
      if (validGoogleAccessToken == null || validGoogleAccessToken.isEmpty) {
        throw Exception('유효한 Google 액세스 토큰을 얻을 수 없습니다.');
      }

      final folderId = await _getFolderIdByName(
        folderName,
        validGoogleAccessToken,
      );
      if (folderId == null) {
        throw Exception('Google Drive에서 "memordo" 폴더를 찾을 수 없습니다.');
      }

      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&pageSize=10',
      );
      final res = await http.get(
        url,
        headers: {'Authorization': 'Bearer $validGoogleAccessToken'},
      );

      if (res.statusCode != 200) {
        throw Exception('파일 목록 조회 실패 (${res.statusCode}): ${res.body}');
      }

      final data = jsonDecode(res.body);
      final files = data['files'] as List;
      if (files.isEmpty) {
        _statusMessage = 'Google Drive에 방문 기록(.jsonl) 파일이 없습니다.';
        _visitHistory = [];
        _filteredVisitHistory = [];
        return;
      }

      final fileId = files[0]['id'];
      final history = await _downloadAndParseJsonl(
        validGoogleAccessToken,
        fileId,
      );

      if (!mounted) return;

      setState(() {
        _visitHistory = history;
        _filteredVisitHistory = List.from(_visitHistory); // 초기에는 전체 기록 표시
        _statusMessage = history.isEmpty ? '방문 기록이 없습니다.' : '';
      });
    } catch (e) {
      print('방문 기록 로드 중 오류: $e');
      if (e.toString().contains('로그인 필요')) {
        _showSnackBar('인증이 필요합니다. 로그인 페이지로 이동합니다.');
        if (mounted)
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => LoginPage()),
          );
      }
      setState(() {
        _statusMessage = '오류 발생: ${e.toString()}';
        _visitHistory = [];
        _filteredVisitHistory = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String?> getValidGoogleAccessToken() async {
    var googleAccessToken = await getStoredGoogleAccessToken();
    if (googleAccessToken == null || googleAccessToken.isEmpty) {
      await refreshGoogleAccessTokenIfNeeded();
      googleAccessToken = await getStoredGoogleAccessToken();
    }
    return googleAccessToken;
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
      return files.isNotEmpty ? files[0]['id'] as String : null;
    }
    return null;
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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var item in _filteredVisitHistory) {
      final timestamp = item['timestamp'] ?? item['visitTime']?.toString();
      if (timestamp == null || timestamp.length < 10) continue;
      final date = timestamp.substring(0, 10);
      groupedByDate.putIfAbsent(date, () => []).add(item);
    }
    final sortedDates =
        groupedByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        // 수정된 검색 UI 디자인 시작
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16.0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                spreadRadius: 2,
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                const Text(
                  '기록 검색',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20.0),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '제목 또는 URL 검색',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.grey.shade600,
                        ),
                        suffixIcon:
                            _searchController.text.isNotEmpty
                                ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () {
                                    _searchController.clear();
                                    _filterHistory('');
                                  },
                                  color: Colors.grey.shade600,
                                )
                                : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8.0,
                        ),
                        isDense: true,
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 수정된 검색 UI 디자인 끝
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16.0),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
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
                _isLoading
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 10),
                          Text(_statusMessage),
                        ],
                      ),
                    )
                    : _filteredVisitHistory.isEmpty &&
                        _searchController.text.isNotEmpty
                    ? Center(
                      child: Text(
                        _statusMessage.isNotEmpty
                            ? _statusMessage
                            : '검색 결과가 없습니다.',
                      ),
                    )
                    : _visitHistory.isEmpty && _searchController.text.isEmpty
                    ? Center(
                      child: Text(
                        _statusMessage.isNotEmpty
                            ? _statusMessage
                            : '불러올 방문 기록이 없습니다.',
                      ),
                    )
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
                          padding: const EdgeInsets.symmetric(vertical: 0.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 8.0,
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

                                return Card(
                                  elevation: 1.0,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 0.0,
                                    horizontal: 8.0,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  color: Colors.white,
                                  child: ListTile(
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
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                              text: TextSpan(
                                                text: url,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.blue.shade700,
                                                  decoration:
                                                      TextDecoration.underline,
                                                  decorationColor:
                                                      Colors.blue.shade700,
                                                ),
                                                recognizer:
                                                    TapGestureRecognizer()
                                                      ..onTap = () async {
                                                        if (url.isNotEmpty) {
                                                          final uri =
                                                              Uri.tryParse(url);
                                                          if (uri != null &&
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
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                      vertical: 0.0,
                                    ),
                                    dense: true,
                                    minVerticalPadding: 0.0,
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        );
                      },
                    ),
          ),
        ),
      ],
    );
  }
}
