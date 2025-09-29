// lib/features/history.dart

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../viewmodels/history_viewmodel.dart';
import '../providers/token_status_provider.dart';
import '../auth/login_page.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const HistoryView();
  }
}

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _filteredHistory = [];

  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tokenProvider = context.read<TokenStatusProvider>();
      final historyViewModel = context.read<HistoryViewModel>();
      _wasAuthenticated = tokenProvider.isAuthenticated;

      if (_wasAuthenticated) {
        historyViewModel.loadVisitHistory().then((_) {
          if (mounted) {
            _filterHistory('');
          }
        });
      }
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
      _filterHistory(_searchController.text);
    });
  }

  void _filterHistory(String query) {
    final viewModel = context.read<HistoryViewModel>();
    final lowerCaseQuery = query.toLowerCase();

    setState(() {
      if (lowerCaseQuery.isEmpty) {
        _filteredHistory = List.from(viewModel.visitHistory);
      } else {
        _filteredHistory =
            viewModel.visitHistory.where((item) {
              final title = item['title']?.toString().toLowerCase() ?? '';
              final url = item['url']?.toString().toLowerCase() ?? '';
              return title.contains(lowerCaseQuery) ||
                  url.contains(lowerCaseQuery);
            }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HistoryViewModel>();
    final tokenProvider = context.watch<TokenStatusProvider>();

    if (tokenProvider.isAuthenticated && !_wasAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        viewModel.loadVisitHistory().then((_) {
          if (mounted) {
            _filterHistory(_searchController.text);
            viewModel.clearSelection();
          }
        });
      });
    }
    _wasAuthenticated = tokenProvider.isAuthenticated;

    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var item in _filteredHistory) {
      final timestamp = item['timestamp'] ?? item['visitTime']?.toString();
      if (timestamp == null || timestamp.length < 10) continue;
      final date = timestamp.substring(0, 10);
      groupedByDate.putIfAbsent(date, () => []).add(item);
    }
    final sortedDates =
        groupedByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '방문 기록 검색...',
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 12.0,
              ),
            ),
          ),
        ),
        Expanded(
          // ✨ [수정] Padding 위젯을 제거하고 ListView.builder에 직접 padding 속성을 적용합니다.
          child:
              !tokenProvider.isAuthenticated
                  ? _buildLoginPrompt(context)
                  : viewModel.isLoading
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(viewModel.status),
                      ],
                    ),
                  )
                  : _filteredHistory.isEmpty
                  ? Center(
                    child: Padding(
                      // Center 안의 Text에는 Padding을 유지해도 괜찮습니다.
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _searchController.text.isNotEmpty
                            ? '검색 결과가 없습니다.'
                            : viewModel.status,
                      ),
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.all(
                      16.0,
                    ), // ✨ [수정] 여기에 padding 적용
                    itemCount: sortedDates.length,
                    itemBuilder: (context, index) {
                      final date = sortedDates[index];
                      final itemsOnDate = groupedByDate[date]!;
                      return _buildDateGroup(context, date, itemsOnDate);
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildDateGroup(
    BuildContext context,
    String date,
    List<Map<String, dynamic>> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          child: Text(
            _formatDateKorean(date),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
        ),
        Column(children: items.map((item) => _buildHistoryItem(item)).toList()),
        const Divider(height: 30, thickness: 0.5, indent: 16, endIndent: 16),
      ],
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final title =
        item['title']?.toString() ?? item['url']?.toString() ?? '제목 없음';
    final url = item['url']?.toString() ?? '';
    final timestamp = item['timestamp'] ?? item['visitTime']?.toString();

    if (timestamp == null) {
      return Container();
    }

    final String uniqueKey = '$timestamp-$url';

    final viewModel = context.read<HistoryViewModel>();
    final bool isChecked = viewModel.selectedUniqueKeys.contains(uniqueKey);

    return InkWell(
      onTap: () {
        viewModel.toggleItemSelection(uniqueKey);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        decoration: BoxDecoration(
          color:
              isChecked
                  ? Theme.of(context).primaryColor.withOpacity(0.1)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: Row(
          children: [
            Transform.scale(
              scale: 0.8,
              child: Checkbox(
                value: isChecked,
                onChanged: (bool? checked) {
                  viewModel.toggleItemSelection(uniqueKey);
                },
                activeColor: Theme.of(context).primaryColor,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (url.isNotEmpty)
                    RichText(
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      text: TextSpan(
                        text: url,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                          overflow: TextOverflow.ellipsis,
                        ),
                        recognizer:
                            TapGestureRecognizer()
                              ..onTap = () async {
                                if (url.isNotEmpty) {
                                  final uri = Uri.tryParse(url);
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                }
                              },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatTime(timestamp),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginPrompt(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 20),
          const Text(
            '로그인이 필요한 기능입니다.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            '방문 기록을 동기화하고 AI 기능을 사용하려면 로그인해주세요.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.login, size: 16),
            label: const Text('로그인 페이지로 이동'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      return yyyyMMdd;
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      DateTime dateTime = DateTime.parse(isoString).toLocal();
      final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final ampm = dateTime.hour < 12 ? '오전' : '오후';
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$ampm $hour12:$minute';
    } catch (_) {
      return '';
    }
  }
}
