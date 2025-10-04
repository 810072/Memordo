// lib/layout/right_sidebar_content.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/page_type.dart';
import '../model/file_system_entry.dart';
import '../providers/file_system_provider.dart';
import 'right_sidebar/memo_sidebar.dart';
import 'right_sidebar/history_sidebar.dart';
import 'right_sidebar/calendar_sidebar.dart';
import 'right_sidebar/graph_sidebar.dart';

class RightSidebarContent extends StatelessWidget {
  final PageType activePage;
  final Function(FileSystemEntry) onEntryTap;
  final Function(FileSystemEntry, String) onRenameEntry; // ✨ [수정] 타입 명확히 함
  final Function(FileSystemEntry) onDeleteEntry;

  const RightSidebarContent({
    Key? key,
    required this.activePage,
    required this.onEntryTap,
    required this.onRenameEntry, // ✨ [수정] 파라미터 다시 추가
    required this.onDeleteEntry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final fileSystemProvider = context.watch<FileSystemProvider>();

    switch (activePage) {
      case PageType.home:
        return MemoSidebar(
          isLoading: fileSystemProvider.isLoading,
          fileSystemEntries: fileSystemProvider.fileSystemEntries,
          onEntryTap: onEntryTap,
          onRefresh: fileSystemProvider.scanForFileSystem,
          onRenameEntry: onRenameEntry, // ✨ [수정] 파라미터 전달
          onDeleteEntry: onDeleteEntry,
        );
      case PageType.history:
        return const HistorySidebar();
      case PageType.graph:
        return const GraphSidebar();
      case PageType.calendar:
        return const CalendarSidebar();
      default:
        return const SizedBox.shrink();
    }
  }
}
