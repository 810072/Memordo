// lib/features/history.dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../viewmodels/history_viewmodel.dart';
import '../layout/bottom_section_controller.dart';
import '../widgets/ai_summary_widget.dart';
import '../features/meeting_screen.dart';
import '../utils/ai_service.dart';
import '../providers/token_status_provider.dart';
import '../auth/login_page.dart';

/// HistoryPage는 ViewModel을 제공하는 역할만 담당합니다.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HistoryViewModel(),
      child: const HistoryView(), // 실제 UI는 HistoryView에서 렌더링
    );
  }
}

/// 실제 UI를 구성하고 ViewModel과 상호작용하는 위젯
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  // ✨ [수정] _selectedTimestamps 대신 _selectedUniqueKeys 사용
  final Set<String> _selectedUniqueKeys = {};
  bool _showSummary = false;

  // 검색 기능 관련 상태 변수
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _filteredHistory = [];

  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tokenProvider = context.read<TokenStatusProvider>();
      _wasAuthenticated = tokenProvider.isAuthenticated;

      if (_wasAuthenticated) {
        context.read<HistoryViewModel>().loadVisitHistory().then((_) {
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

  void _handleSummarizeAction() {
    final viewModel = context.read<HistoryViewModel>();
    final bottomController = context.read<BottomSectionController>();

    if (bottomController.isLoading) return;

    // ✨ [수정] _selectedUniqueKeys 사용
    if (_selectedUniqueKeys.length == 1) {
      final selectedUniqueKey = _selectedUniqueKeys.first;
      // uniqueKey에서 URL을 파싱해냅니다.
      // 예: "2023-10-27T10:30:00.000Z-http://example.com/page1"
      // 마지막 하이픈 이후가 URL이라고 가정
      final lastHyphenIndex = selectedUniqueKey.lastIndexOf('-');

      String? selectedUrl;
      if (lastHyphenIndex != -1 &&
          lastHyphenIndex < selectedUniqueKey.length - 1) {
        selectedUrl = selectedUniqueKey.substring(lastHyphenIndex + 1);
      } else {
        // 하이픈이 없거나 마지막에 있는 경우, URL로 간주하기 어렵습니다.
        // 또는 timestamp만으로 구성된 경우 (이전 로직과의 호환성을 위해)
        selectedUrl = selectedUniqueKey; // 일단 전체를 URL로 시도
      }

      if (selectedUrl != null && selectedUrl.isNotEmpty) {
        setState(() => _showSummary = true);

        bottomController.setIsLoading(true);
        bottomController.updateSummary('URL 요약 중...\n$selectedUrl');

        crawlAndSummarizeUrl(selectedUrl).then((summary) {
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
        });
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
            _selectedUniqueKeys
                    .isEmpty // ✨ [수정] _selectedUniqueKeys 사용
                ? '내용을 요약할 URL을 선택해주세요.'
                : '내용을 요약할 URL은 하나만 선택할 수 있습니다.',
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
  }

  void _createNewMemoWithSummary() {
    final bottomController = context.read<BottomSectionController>();
    final summary = bottomController.summaryText;

    if (summary.isNotEmpty && !summary.contains('실패')) {
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
    final viewModel = context.watch<HistoryViewModel>();
    final bottomController = context.watch<BottomSectionController>();
    final tokenProvider = context.watch<TokenStatusProvider>();

    if (tokenProvider.isAuthenticated && !_wasAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<HistoryViewModel>().loadVisitHistory().then((_) {
          if (mounted) {
            _filterHistory(_searchController.text);
            _selectedUniqueKeys.clear(); // ✨ [수정] _selectedUniqueKeys 초기화
            _showSummary = false;
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
        Container(
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).appBarTheme.backgroundColor,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '방문 기록',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 22),
                    tooltip: '새로고침',
                    onPressed:
                        viewModel.isLoading || !tokenProvider.isAuthenticated
                            ? null
                            : () => context
                                .read<HistoryViewModel>()
                                .loadVisitHistory()
                                .then((_) {
                                  if (mounted) {
                                    _filterHistory(_searchController.text);
                                  }
                                }),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.summarize_outlined, size: 18),
                    label: const Text("선택 항목 요약"),
                    onPressed:
                        !tokenProvider.isAuthenticated
                            ? null
                            : _handleSummarizeAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3d98f4),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
          child: Padding(
            padding: const EdgeInsets.all(16.0),
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
                      child: Text(
                        _searchController.text.isNotEmpty
                            ? '검색 결과가 없습니다.'
                            : viewModel.status,
                      ),
                    )
                    : ListView.builder(
                      itemCount: sortedDates.length,
                      itemBuilder: (context, index) {
                        final date = sortedDates[index];
                        final itemsOnDate = groupedByDate[date]!;
                        return _buildDateGroup(context, date, itemsOnDate);
                      },
                    ),
          ),
        ),
        if (_showSummary && tokenProvider.isAuthenticated)
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(
                      top: 16.0,
                      right: 16.0,
                      bottom: 8.0,
                    ),
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
                    child: const AiSummaryWidget(),
                  ),
                ),
                if (!bottomController.isLoading &&
                    bottomController.summaryText.isNotEmpty &&
                    !bottomController.summaryText.contains("실패"))
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0, bottom: 16.0),
                    child: Align(
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
                  ),
              ],
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
      // timestamp가 없으면 선택 불가하게 처리하거나,
      // 아예 렌더링하지 않거나, 대체 키를 생성하는 로직 추가
      return Container(); // 이 경우 해당 항목은 렌더링되지 않습니다.
    }

    // ✨ [수정] timestamp와 URL을 조합하여 고유한 키를 만듭니다.
    // 이는 timestamp만으로는 고유하지 않은 경우를 대비합니다.
    final String uniqueKey = '$timestamp-$url';

    final time = _formatTime(timestamp);
    final bool isChecked = _selectedUniqueKeys.contains(
      uniqueKey,
    ); // ✨ [수정] uniqueKey 사용

    return InkWell(
      onTap: () {
        setState(() {
          if (isChecked) {
            _selectedUniqueKeys.remove(uniqueKey); // ✨ [수정] uniqueKey 사용
          } else {
            _selectedUniqueKeys.add(uniqueKey); // ✨ [수정] uniqueKey 사용
          }
        });
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
                  setState(() {
                    if (checked == true) {
                      _selectedUniqueKeys.add(uniqueKey); // ✨ [수정] uniqueKey 사용
                    } else {
                      _selectedUniqueKeys.remove(
                        uniqueKey,
                      ); // ✨ [수정] uniqueKey 사용
                    }
                  });
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
              time,
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
