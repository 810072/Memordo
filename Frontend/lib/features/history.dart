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
  final Set<String> _selectedTimestamps = {};
  bool _showSummary = false;

  // 검색 기능 관련 상태 변수
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _filteredHistory = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tokenProvider = context.read<TokenStatusProvider>();
      if (tokenProvider.isAuthenticated) {
        // 데이터 로드 후 필터링된 리스트 초기화
        context.read<HistoryViewModel>().loadVisitHistory().then((_) {
          if (mounted) {
            _filterHistory(''); // 초기에 전체 리스트로 채움
          }
        });
      }
    });
    // 검색 컨트롤러에 리스너 추가
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    // 컨트롤러 및 타이머 dispose
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // 검색어 변경 시 디바운싱 처리
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _filterHistory(_searchController.text);
    });
  }

  // 방문 기록 필터링 로직
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

    if (_selectedTimestamps.length == 1) {
      final selectedTimestamp = _selectedTimestamps.first;
      String? selectedUrl;

      for (var item in viewModel.visitHistory) {
        final timestamp = item['timestamp'] ?? item['visitTime'];
        if (timestamp == selectedTimestamp) {
          selectedUrl = item['url'] as String?;
          break;
        }
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

    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    // 필터링된 리스트를 사용하여 날짜별로 그룹화합니다.
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
                            // 새로고침 후 필터링된 리스트도 갱신합니다.
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
        // ✨ [수정] 검색창의 높이를 조절합니다.
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
              // isDense를 true로 설정하고 contentPadding을 조절하여 높이를 줄입니다.
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
                    // 필터링된 리스트가 비었는지 확인합니다.
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
    final time = _formatTime(timestamp);
    final bool isChecked = _selectedTimestamps.contains(timestamp);

    return InkWell(
      onTap: () {
        if (timestamp == null) return;
        setState(() {
          if (isChecked) {
            _selectedTimestamps.remove(timestamp);
          } else {
            _selectedTimestamps.add(timestamp);
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
                  if (timestamp == null) return;
                  setState(() {
                    if (checked == true) {
                      _selectedTimestamps.add(timestamp);
                    } else {
                      _selectedTimestamps.remove(timestamp);
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
              ).then((_) {
                final tokenProvider = context.read<TokenStatusProvider>();
                if (tokenProvider.isAuthenticated) {
                  context.read<HistoryViewModel>().loadVisitHistory();
                }
              });
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
