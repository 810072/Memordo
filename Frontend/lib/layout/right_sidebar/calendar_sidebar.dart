// lib/layout/right_sidebar/calendar_sidebar.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/calendar_viewmodel.dart';
import '../../viewmodels/calendar_sidebar_viewmodel.dart';

class CalendarSidebar extends StatefulWidget {
  const CalendarSidebar({Key? key}) : super(key: key);

  @override
  State<CalendarSidebar> createState() => _CalendarSidebarState();
}

class _CalendarSidebarState extends State<CalendarSidebar> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _taskController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final viewModel = Provider.of<CalendarSidebarViewModel>(
      context,
      listen: false,
    );
    viewModel.loadTasks();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final calendarViewModel = Provider.of<CalendarViewModel>(
        context,
        listen: false,
      );
      viewModel.updateStats(calendarViewModel.focusedDay);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewModel = context.watch<CalendarSidebarViewModel>();
    final calendarViewModel = context.watch<CalendarViewModel>();

    // 월이 변경되면 통계 업데이트
    WidgetsBinding.instance.addPostFrameCallback((_) {
      viewModel.updateStats(calendarViewModel.focusedDay);
    });

    return Column(
      children: [
        // 월간 통계 (상단 1/3)
        Expanded(
          flex: 13,
          child: _buildMonthlyStats(theme, viewModel, calendarViewModel),
        ),
        Divider(height: 1, color: theme.dividerColor),
        // 메모 검색 (하단 1/3)
        Expanded(flex: 12, child: _buildMemoSearch(theme, viewModel)),
        Divider(height: 1, color: theme.dividerColor),
        // 빠른 할일 목록 (중간 1/3)
        Expanded(flex: 12, child: _buildQuickTasks(theme, viewModel)),
      ],
    );
  }

  // 월간 통계 섹션
  Widget _buildMonthlyStats(
    ThemeData theme,
    CalendarSidebarViewModel viewModel,
    CalendarViewModel calendarViewModel,
  ) {
    final stats = viewModel.monthlyStats;

    return Container(
      color: theme.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40.0,
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.bar_chart, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${DateFormat('yyyy년 M월').format(calendarViewModel.focusedDay)} 통계',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(6.0),
              child: Column(
                children: [
                  _buildStatItem(
                    icon: Icons.edit_calendar,
                    label: '메모 작성 일수',
                    value: '${stats['daysWithMemo']}일',
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 6),
                  _buildStatItem(
                    icon: Icons.notes,
                    label: '총 메모 수',
                    value: '${stats['totalMemos']}개',
                    color: Colors.green,
                  ),
                  const SizedBox(height: 6),
                  _buildStatItem(
                    icon: Icons.local_fire_department,
                    label: '연속 작성',
                    value: '${stats['streak']}일',
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 6),
                  _buildStatItem(
                    icon: Icons.star,
                    label: '가장 활발한 요일',
                    value: stats['mostActiveDay'] ?? '-',
                    color: Colors.purple,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 빠른 할일 목록 섹션
  Widget _buildQuickTasks(ThemeData theme, CalendarSidebarViewModel viewModel) {
    return Container(
      color: theme.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.checklist, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '빠른 할일',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${viewModel.completedTasksCount}/${viewModel.tasks.length}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskController,
                    decoration: InputDecoration(
                      hintText: '할일 추가...',
                      hintStyle: const TextStyle(fontSize: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 8.0,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        viewModel.addTask(value.trim());
                        _taskController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () {
                    if (_taskController.text.trim().isNotEmpty) {
                      viewModel.addTask(_taskController.text.trim());
                      _taskController.clear();
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                viewModel.tasks.isEmpty
                    ? Center(
                      child: Text(
                        '할일을 추가해보세요',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    )
                    : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      itemCount: viewModel.tasks.length,
                      onReorder: (oldIndex, newIndex) {
                        viewModel.reorderTasks(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final task = viewModel.tasks[index];
                        return Dismissible(
                          key: Key(task.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16.0),
                            color: Colors.red,
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) {
                            viewModel.deleteTask(task.id);
                          },
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                            ),
                            leading: Checkbox(
                              value: task.isCompleted,
                              onChanged: (value) {
                                viewModel.toggleTask(task.id);
                              },
                            ),
                            title: Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 12,
                                decoration:
                                    task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                color:
                                    task.isCompleted
                                        ? Colors.grey.shade400
                                        : Colors.black,
                              ),
                            ),
                            //trailing: const Icon(Icons.drag_handle, size: 16),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  // 메모 검색 섹션
  Widget _buildMemoSearch(ThemeData theme, CalendarSidebarViewModel viewModel) {
    return Container(
      color: theme.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, size: 18),
                SizedBox(width: 8),
                Text(
                  '메모 검색',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '메모 내용 검색...',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            viewModel.searchMemos('');
                          },
                        )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 8.0,
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (value) {
                viewModel.searchMemos(value);
              },
            ),
          ),
          Expanded(
            child:
                viewModel.isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : viewModel.searchResults.isEmpty &&
                        _searchController.text.isNotEmpty
                    ? Center(
                      child: Text(
                        '검색 결과가 없습니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    )
                    : viewModel.searchResults.isEmpty
                    ? Center(
                      child: Text(
                        '메모를 검색해보세요',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      itemCount: viewModel.searchResults.length,
                      itemBuilder: (context, index) {
                        final result = viewModel.searchResults[index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 4.0,
                          ),
                          leading: const Icon(Icons.event_note, size: 18),
                          title: Text(
                            DateFormat(
                              'yyyy-MM-dd (E)',
                              'ko_KR',
                            ).format(result.date),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            result.content,
                            style: const TextStyle(fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            // 해당 날짜로 이동
                            Provider.of<CalendarViewModel>(
                              context,
                              listen: false,
                            ).onDaySelected(result.date, result.date);
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
