// lib/features/search_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/login_page.dart';
import '../model/file_system_entry.dart';
import '../providers/file_system_provider.dart';
import '../services/auth_token.dart';

enum SearchType { history, files, calendar }

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  SearchType _selectedType = SearchType.history;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;
  String _statusMessage = '데이터를 불러오는 중...';

  List<dynamic> _allItems = [];
  List<dynamic> _filteredItems = [];
  final List<bool> _isSelected = [true, false, false];

  @override
  void initState() {
    super.initState();
    _loadDataForSelectedType();
    _searchController.addListener(_onSearchChanged);
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
      _filterItems(_searchController.text);
    });
  }

  Future<void> _loadDataForSelectedType() async {
    setState(() {
      _isLoading = true;
      _filteredItems = [];
      _statusMessage = '데이터를 불러오는 중...';
    });

    try {
      switch (_selectedType) {
        case SearchType.history:
          _allItems = await _loadHistory();
          break;
        case SearchType.files:
          _allItems = await _loadFiles();
          break;
        case SearchType.calendar:
          _allItems = await _loadCalendarMemos();
          break;
      }
      _statusMessage = _allItems.isEmpty ? '표시할 내용이 없습니다.' : '';
    } catch (e) {
      _statusMessage = '오류 발생: ${e.toString()}';
      if (e.toString().contains('로그인 필요')) {
        _showSnackBar('인증이 필요합니다. 로그인 페이지로 이동합니다.');
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => LoginPage()),
          );
        }
      }
    }

    setState(() {
      _isLoading = false;
      _filterItems(_searchController.text);
    });
  }

  // 데이터 로더 함수들...
  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final googleAccessToken = await getValidGoogleAccessToken();
    if (googleAccessToken == null) throw Exception('Google 로그인 필요.');

    const folderName = 'memordo';
    final folderId = await _getFolderIdByName(folderName, googleAccessToken);
    if (folderId == null) throw Exception('memordo 폴더를 찾을 수 없습니다.');

    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=%27$folderId%27+in+parents+and+name+contains+%27.jsonl%27&orderBy=createdTime+desc&pageSize=10',
    );
    final res = await http.get(
      url,
      headers: {'Authorization': 'Bearer $googleAccessToken'},
    );

    if (res.statusCode != 200)
      throw Exception('파일 목록 조회 실패 (${res.statusCode})');

    final data = jsonDecode(res.body);
    final files = data['files'] as List;
    if (files.isEmpty) return [];

    final fileId = files[0]['id'];
    final history = await _downloadAndParseJsonl(googleAccessToken, fileId);
    history.sort((a, b) {
      final at = a['timestamp'] ?? a['visitTime']?.toString() ?? '';
      final bt = b['timestamp'] ?? b['visitTime']?.toString() ?? '';
      return bt.compareTo(at);
    });
    return history;
  }

  Future<List<FileSystemEntry>> _loadFiles() async {
    final fileProvider = Provider.of<FileSystemProvider>(
      context,
      listen: false,
    );
    await fileProvider.scanForFileSystem();

    List<FileSystemEntry> allFiles = [];

    void flatten(List<FileSystemEntry> entries) {
      for (var entry in entries) {
        if (entry.isDirectory) {
          if (entry.children != null) {
            flatten(entry.children!);
          }
        } else {
          allFiles.add(entry);
        }
      }
    }

    flatten(fileProvider.fileSystemEntries);
    return allFiles;
  }

  Future<List<Map<String, dynamic>>> _loadCalendarMemos() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('memoData');
    if (jsonString == null) return [];

    final Map<String, dynamic> decoded = jsonDecode(jsonString);
    final List<Map<String, dynamic>> memos = [];
    decoded.forEach((key, value) {
      if (value.toString().trim().isNotEmpty) {
        memos.add({'date': DateTime.parse(key), 'memo': value});
      }
    });
    memos.sort((a, b) => (b['date'] as DateTime).compareTo(a['date']));
    return memos;
  }

  void _filterItems(String query) {
    final lowerCaseQuery = query.toLowerCase();
    setState(() {
      if (lowerCaseQuery.isEmpty) {
        _filteredItems = List.from(_allItems);
      } else {
        _filteredItems =
            _allItems.where((item) {
              if (_selectedType == SearchType.history) {
                final title = item['title']?.toString().toLowerCase() ?? '';
                final url = item['url']?.toString().toLowerCase() ?? '';
                return title.contains(lowerCaseQuery) ||
                    url.contains(lowerCaseQuery);
              } else if (_selectedType == SearchType.files) {
                final file = item as FileSystemEntry;
                final name = file.name.toLowerCase();
                return name.contains(lowerCaseQuery);
              } else if (_selectedType == SearchType.calendar) {
                final memo = item['memo']?.toString().toLowerCase() ?? '';
                return memo.contains(lowerCaseQuery);
              }
              return false;
            }).toList();
      }
      _statusMessage =
          _filteredItems.isEmpty && lowerCaseQuery.isNotEmpty
              ? '검색 결과가 없습니다.'
              : '표시할 내용이 없습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            decoration: BoxDecoration(
              color: theme.cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildToggleButtons(theme),
                const SizedBox(height: 16),
                _buildSearchField(theme),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child:
                  _isLoading
                      ? Center(
                        key: const ValueKey('loading'),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(_statusMessage),
                          ],
                        ),
                      )
                      : _filteredItems.isEmpty
                      ? Center(
                        key: ValueKey(_selectedType),
                        child: Text(_statusMessage),
                      )
                      : _buildResultsList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButtons(ThemeData theme) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ToggleButtons(
        isSelected: _isSelected,
        onPressed: (index) {
          setState(() {
            for (int i = 0; i < _isSelected.length; i++) {
              _isSelected[i] = i == index;
            }
            _selectedType = SearchType.values[index];
          });
          _loadDataForSelectedType();
        },
        borderRadius: BorderRadius.circular(12),
        selectedColor: Colors.white,
        color: theme.textTheme.bodyLarge?.color,
        fillColor: theme.primaryColor,
        splashColor: theme.primaryColor.withOpacity(0.12),
        hoverColor: theme.primaryColor.withOpacity(0.04),
        borderWidth: 0,
        selectedBorderColor: theme.primaryColor,
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Icon(Icons.history, size: 16),
                SizedBox(width: 8),
                Text('방문 기록'),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16),
                SizedBox(width: 8),
                Text('파일'),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 16),
                SizedBox(width: 8),
                Text('캘린더'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: '검색...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon:
            _searchController.text.isNotEmpty
                ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
                : null,
        border: InputBorder.none,
        filled: true,
        fillColor: theme.scaffoldBackgroundColor,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.primaryColor, width: 2),
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    if (_selectedType == SearchType.history) {
      return _buildGroupedHistoryList();
    }

    return ListView.builder(
      key: ValueKey(_selectedType),
      padding: const EdgeInsets.all(16.0),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        switch (_selectedType) {
          case SearchType.history:
            if (item is Map<String, dynamic>) return _buildHistoryItem(item);
            break;
          case SearchType.files:
            if (item is FileSystemEntry) return _buildFileItem(item);
            break;
          case SearchType.calendar:
            if (item is Map<String, dynamic>) return _buildCalendarItem(item);
            break;
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildGroupedHistoryList() {
    final Map<String, List<dynamic>> groupedByDate = {};
    for (var item in _filteredItems) {
      final timestamp = item['timestamp'] ?? item['visitTime']?.toString();
      if (timestamp == null || timestamp.length < 10) continue;
      final date = timestamp.substring(0, 10);
      groupedByDate.putIfAbsent(date, () => []).add(item);
    }
    final sortedDates = groupedByDate.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final itemsOnDate = groupedByDate[date]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16.0, bottom: 8.0, left: 8.0),
              child: Text(
                _formatDateKorean(date),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
            ),
            ...itemsOnDate
                .map((item) => _buildHistoryItem(item as Map<String, dynamic>))
                .toList(),
          ],
        );
      },
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? '제목 없음';
    final url = item['url']?.toString() ?? '';
    final time = _formatTime(
      item['timestamp'] ?? item['visitTime']?.toString(),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(Icons.public, color: Colors.grey, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // ✨ [수정] URL을 RichText로 변경하여 하이퍼링크 스타일 적용
                    RichText(
                      text: TextSpan(
                        text: url,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer:
                            TapGestureRecognizer()
                              ..onTap = () async {
                                final uri = Uri.tryParse(url);
                                if (uri != null && await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                time,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileItem(FileSystemEntry item) {
    final fileProvider = Provider.of<FileSystemProvider>(
      context,
      listen: false,
    );
    final notesDir = fileProvider.lastSavedDirectoryPath ?? '';
    final relativePath =
        notesDir.isNotEmpty
            ? p.relative(item.path, from: p.dirname(notesDir))
            : item.path;

    return InkWell(
      onTap: () {
        /* 파일 열기 로직 추가 */
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              color: Colors.blueGrey.shade400,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basenameWithoutExtension(item.name),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.dirname(relativePath),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarItem(Map<String, dynamic> item) {
    final memo = item['memo']?.toString() ?? '';
    final date = item['date'] as DateTime;

    return InkWell(
      onTap: () {
        /* 캘린더 해당 날짜로 이동 로직 추가 */
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.event_note_outlined,
              color: Colors.teal.shade400,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memo,
                    style: const TextStyle(height: 1.4),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat('yyyy년 MM월 dd일').format(date),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> getValidGoogleAccessToken() async {
    var token = await getStoredGoogleAccessToken();
    if (token == null || token.isEmpty) {
      await refreshGoogleAccessTokenIfNeeded();
      token = await getStoredGoogleAccessToken();
    }
    return token;
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
    if (res.statusCode != 200)
      throw Exception('파일 다운로드 실패 (${res.statusCode})');
    final lines = const LineSplitter().convert(utf8.decode(res.bodyBytes));
    return lines
        .where((line) => line.trim().isNotEmpty)
        .map<Map<String, dynamic>>((line) => jsonDecode(line))
        .toList();
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('HH:mm').format(dateTime);
    } catch (e) {
      return '';
    }
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
}
