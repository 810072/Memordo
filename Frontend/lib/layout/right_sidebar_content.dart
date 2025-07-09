// lib/layout/right_sidebar_content.dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../model/file_system_entry.dart';
import '../widgets/expandable_folder_tile.dart';

class RightSidebarContent extends StatelessWidget {
  final bool isLoading;
  final List<FileSystemEntry> fileSystemEntries;
  final Function(FileSystemEntry) onEntryTap;
  final VoidCallback onRefresh;
  final Function(FileSystemEntry) onRenameEntry;
  final Function(FileSystemEntry) onDeleteEntry;
  final bool sidebarIsExpanded;

  const RightSidebarContent({
    Key? key,
    required this.isLoading,
    required this.fileSystemEntries,
    required this.onEntryTap,
    required this.onRefresh,
    required this.onRenameEntry,
    required this.onDeleteEntry,
    required this.sidebarIsExpanded,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "저장된 메모",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                      fontFamily: 'Work Sans',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  tooltip: "새로고침",
                  onPressed: isLoading ? null : onRefresh,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tight(const Size(28, 28)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          const SizedBox(height: 5),
          if (isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (fileSystemEntries.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "저장된 메모가 없습니다.\n'.md 파일로 저장' 기능을 사용해보세요.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: fileSystemEntries.length,
                itemBuilder: (context, index) {
                  final entry = fileSystemEntries[index];
                  return _buildFileSystemEntry(
                    context,
                    entry,
                    onEntryTap,
                    onRenameEntry,
                    onDeleteEntry,
                    0,
                    sidebarIsExpanded,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileSystemEntry(
    BuildContext context,
    FileSystemEntry entry,
    Function(FileSystemEntry) onEntryTap,
    Function(FileSystemEntry) onRenameEntry,
    Function(FileSystemEntry) onDeleteEntry,
    int indentLevel,
    bool sidebarIsExpanded,
  ) {
    final double itemHeight = 24.0;
    // sidebarIsExpanded 상태에 따라 들여쓰기 레벨당 간격만 조절합니다.
    // 화살표 공간은 ExpandableFolderTile에서 직접 처리하므로 여기서는 제거합니다.
    final double indentPerLevel = sidebarIsExpanded ? 15.0 : 0.0;
    final double effectivePaddingLeft = (indentLevel * indentPerLevel);

    final Color defaultTextColor = Colors.grey.shade800;
    final Color fileIconColor = Colors.grey.shade500;
    final Color folderIconColor = Colors.blueGrey.shade600;
    // final Color arrowColor = Colors.grey; // arrowColor는 이제 ExpandableFolderTile 내부에서 사용됩니다.

    if (entry.isDirectory) {
      return ExpandableFolderTile(
        key: PageStorageKey(entry.path),
        itemHeight: itemHeight,
        arrowColor: Colors.grey, // ExpandableFolderTile로 arrowColor 전달
        folderIcon: Padding(
          // 폴더 아이콘 앞에 들여쓰기 패딩만 적용합니다.
          // ExpandableFolderTile이 화살표 공간을 자체적으로 제공하므로 여기서는 0.0을 사용
          padding: EdgeInsets.only(
            left: effectivePaddingLeft + (sidebarIsExpanded ? 0.0 : 0.0),
          ),
          child: Icon(Icons.folder, size: 16, color: folderIconColor),
        ),
        title: Text(
          entry.name,
          style: TextStyle(
            color: defaultTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Work Sans',
          ),
          overflow: TextOverflow.ellipsis,
        ),
        children:
            entry.children!.map((child) {
              return _buildFileSystemEntry(
                context,
                child,
                onEntryTap,
                onRenameEntry,
                onDeleteEntry,
                indentLevel + 1,
                sidebarIsExpanded,
              );
            }).toList(),
      );
    } else {
      // 파일 항목은 ExpandableFolderTile을 사용하지 않으므로, 직접 패딩과 Row를 구성합니다.
      // 화살표 아이콘 공간(20px) + 아이콘과 텍스트 사이의 간격(4px)만큼을 패딩으로 더합니다.
      final double totalLeftFixedSpaceForFile =
          (sidebarIsExpanded
              ? 20.0 + 4.0
              : 0.0 +
                  4.0); // 20px (arrow) + 4px (icon-text separation) when expanded
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onEntryTap(entry),
          borderRadius: BorderRadius.zero,
          hoverColor: Colors.grey[200],
          child: SizedBox(
            height: itemHeight,
            child: Padding(
              padding: EdgeInsets.only(
                // 들여쓰기 + 화살표 공간 + 폴더/파일 아이콘까지의 공간
                left: effectivePaddingLeft + totalLeftFixedSpaceForFile,
                right: 8.0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: fileIconColor,
                  ),
                  const SizedBox(width: 4), // 파일 아이콘과 이름 사이의 간격
                  Expanded(
                    child: Text(
                      p.basenameWithoutExtension(entry.name),
                      style: TextStyle(
                        color: defaultTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        fontFamily: 'Work Sans',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildEntryActions(
                    context,
                    entry,
                    onRenameEntry,
                    onDeleteEntry,
                    itemHeight,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildEntryActions(
    BuildContext context,
    FileSystemEntry entry,
    Function(FileSystemEntry) onRenameEntry,
    Function(FileSystemEntry) onDeleteEntry,
    double parentItemHeight,
  ) {
    final double iconSize = parentItemHeight * 0.7;

    return SizedBox(
      height: parentItemHeight,
      width: parentItemHeight,
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'rename') {
            onRenameEntry(entry);
          } else if (value == 'delete') {
            onDeleteEntry(entry);
          }
        },
        itemBuilder:
            (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'rename',
                height: 28,
                child: Text('이름 변경', style: TextStyle(fontSize: 12)),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                height: 28,
                child: Text('삭제', style: TextStyle(fontSize: 12)),
              ),
            ],
        icon: Icon(
          Icons.more_vert,
          size: iconSize,
          color: Colors.grey.shade500,
        ),
        tooltip: '더보기',
        padding: EdgeInsets.zero,
        splashRadius: 16,
      ),
    );
  }
}
