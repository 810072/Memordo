// lib/features/search_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/file_system_entry.dart';
import '../providers/file_system_provider.dart';

// history 타입을 제거합니다.
enum SearchType { files, calendar }

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  // 기본 선택 타입을 files로 변경합니다.
  SearchType _selectedType = SearchType.files;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;
  String _statusMessage = '데이터를 불러오는 중...';

  List<dynamic> _allItems = [];
  List<dynamic> _filteredItems = [];
  // isSelected 배열의 길이를 2로 줄입니다.
  final List<bool> _isSelected = [true, false];

  @override
  void initState() {
    super.initState();
    // ✨ [수정] 위젯 빌드가 완료된 후 데이터를 로드하도록 변경
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataForSelectedType();
    });
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
      _allItems = [];
      _filteredItems = [];
      _statusMessage = '데이터를 불러오는 중...';
    });

    try {
      // history 케이스를 제거합니다.
      switch (_selectedType) {
        case SearchType.files:
          _allItems = await _loadFiles();
          break;
        case SearchType.calendar:
          _allItems = await _loadCalendarMemos();
          break;
      }
      _statusMessage = _allItems.isEmpty ? '표시할 내용이 없습니다.' : '';
    } catch (e) {
      // 오류 메시지를 단순화합니다.
      _statusMessage = '오류 발생: ${e.toString()}';
    }

    setState(() {
      _isLoading = false;
      _filterItems(_searchController.text);
    });
  }

  Future<List<FileSystemEntry>> _loadFiles() async {
    // context.mounted 체크 추가
    if (!mounted) return [];
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
              // history 케이스를 제거합니다.
              if (_selectedType == SearchType.files) {
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
      // 로그인 관련 메시지 처리 로직을 제거합니다.
      if (_filteredItems.isEmpty && lowerCaseQuery.isNotEmpty) {
        _statusMessage = '검색 결과가 없습니다.';
      } else if (_allItems.isEmpty) {
        _statusMessage = '표시할 내용이 없습니다.';
      }
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
                      // 로그인 프롬프트 표시 로직을 제거하고 단순화합니다.
                      : _filteredItems.isEmpty
                      ? Center(
                        key: ValueKey('empty_${_selectedType}'),
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
        // 방문 기록 버튼을 제거합니다.
        children: const [
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
    // history 관련 분기 로직을 제거합니다.
    return ListView.builder(
      key: ValueKey(_selectedType),
      padding: const EdgeInsets.all(16.0),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        switch (_selectedType) {
          case SearchType.files:
            return _buildFileItem(item as FileSystemEntry);
          case SearchType.calendar:
            return _buildCalendarItem(item as Map<String, dynamic>);
        }
      },
    );
  }

  Widget _buildFileItem(FileSystemEntry item) {
    // context.mounted 체크 추가
    if (!mounted) return const SizedBox.shrink();
    final fileProvider = Provider.of<FileSystemProvider>(
      context,
      listen: false,
    );
    final notesDir = fileProvider.lastSavedDirectoryPath ?? '';
    final relativePath =
        notesDir.isNotEmpty && p.isWithin(notesDir, item.path)
            ? p.relative(item.path, from: p.dirname(notesDir))
            : item.path;

    return InkWell(
      onTap: () {
        // TODO: 파일 열기 로직 구현
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
        // TODO: 캘린더 해당 날짜로 이동 로직 구현
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
}
