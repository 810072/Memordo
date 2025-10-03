// lib/features/history.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../viewmodels/history_viewmodel.dart';
import '../providers/token_status_provider.dart';
import '../auth/auth_dialog.dart';

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
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tokenProvider = context.read<TokenStatusProvider>();
      final historyViewModel = context.read<HistoryViewModel>();
      _wasAuthenticated = tokenProvider.isAuthenticated;

      if (_wasAuthenticated && historyViewModel.filteredHistory.isEmpty) {
        historyViewModel.loadVisitHistory();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HistoryViewModel>();
    final tokenProvider = context.watch<TokenStatusProvider>();

    if (tokenProvider.isAuthenticated && !_wasAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        viewModel.loadVisitHistory();
      });
    }
    _wasAuthenticated = tokenProvider.isAuthenticated;

    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};
    for (var item in viewModel.filteredHistory) {
      final timestamp = item['timestamp'] ?? item['visitTime']?.toString();
      if (timestamp == null || timestamp.length < 10) continue;
      final date = timestamp.substring(0, 10);
      groupedByDate.putIfAbsent(date, () => []).add(item);
    }

    // ✨ [수정] ViewModel의 sortOrder에 따라 날짜 그룹의 순서를 결정
    final sortedDates = groupedByDate.keys.toList();
    if (viewModel.sortOrder == SortOrder.latest) {
      sortedDates.sort((a, b) => b.compareTo(a));
    } else {
      sortedDates.sort((a, b) => a.compareTo(b));
    }

    return !tokenProvider.isAuthenticated
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
        : viewModel.filteredHistory.isEmpty
        ? Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              viewModel.isFilterActive ? '필터 결과가 없습니다.' : viewModel.status,
            ),
          ),
        )
        : ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: sortedDates.length,
          itemBuilder: (context, index) {
            final date = sortedDates[index];
            final itemsOnDate = groupedByDate[date]!;
            return _buildDateGroup(context, date, itemsOnDate);
          },
        );
  }

  Widget _buildDateGroup(
    BuildContext context,
    String date,
    List<Map<String, dynamic>> items,
  ) {
    // ... (기존과 동일)
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
    // ... (기존과 동일)
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
    // ... (기존과 동일)
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
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                  return const AuthDialog();
                },
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
    // ... (기존과 동일)
    try {
      final date = DateTime.parse(yyyyMMdd);
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      return '${date.year}년 ${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
    } catch (_) {
      return yyyyMMdd;
    }
  }

  String _formatTime(String? isoString) {
    // ... (기존과 동일)
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
