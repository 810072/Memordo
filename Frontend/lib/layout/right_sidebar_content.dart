// lib/layout/right_sidebar_content.dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../model/file_system_entry.dart';
import '../widgets/expandable_folder_tile.dart'; // ExpandableFolderTile 위젯 임포트

class RightSidebarContent extends StatelessWidget {
  final bool isLoading;
  final List<FileSystemEntry> fileSystemEntries;
  final Function(FileSystemEntry) onEntryTap;
  final VoidCallback onRefresh;
  final Function(FileSystemEntry) onRenameEntry;
  final Function(FileSystemEntry) onDeleteEntry;

  const RightSidebarContent({
    Key? key,
    required this.isLoading,
    required this.fileSystemEntries,
    required this.onEntryTap,
    required this.onRefresh,
    required this.onRenameEntry,
    required this.onDeleteEntry,
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
                Text(
                  "저장된 메모",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                    fontFamily: 'Work Sans',
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
  ) {
    final double itemHeight = 24.0; // 항목 높이 통일
    final double arrowSpace = 20.0; // ExpandableFolderTile에서 화살표에 할당한 공간
    final double indentPerLevel = 15.0; // 각 레벨당 추가 들여쓰기
    final double effectivePaddingLeft = (indentLevel * indentPerLevel);

    final Color defaultTextColor = Colors.grey.shade800;
    final Color fileIconColor = Colors.grey.shade500;
    final Color folderIconColor = Colors.blueGrey.shade600;
    final Color arrowColor = Colors.grey;

    if (entry.isDirectory) {
      return ExpandableFolderTile(
        key: PageStorageKey(entry.path),
        itemHeight: itemHeight,
        arrowColor: arrowColor,
        folderIcon: Padding(
          padding: EdgeInsets.only(left: effectivePaddingLeft),
          child: Icon(Icons.folder, size: 16, color: folderIconColor),
        ),
        // ✅ 폴더 이름과 더보기 아이콘을 포함하는 Row의 높이와 정렬을 맞춥니다.
        title: SizedBox(
          // Row의 높이를 itemHeight에 맞춤
          height: itemHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center, // 세로 중앙 정렬
            children: [
              Expanded(
                child: Text(
                  entry.name,
                  style: TextStyle(
                    color: defaultTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Work Sans',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // ✅ 폴더에 대한 액션 버튼 추가
              _buildEntryActions(
                context,
                entry,
                onRenameEntry,
                onDeleteEntry,
                itemHeight, // ✅ itemHeight 전달
              ),
            ],
          ),
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
              );
            }).toList(),
      );
    } else {
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
                left: effectivePaddingLeft + arrowSpace,
                right: 8.0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center, // 세로 중앙 정렬
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: fileIconColor,
                  ),
                  const SizedBox(width: 5),
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
                    itemHeight, // ✅ itemHeight 전달
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
    double parentItemHeight, // ✅ 부모 항목의 높이를 인자로 받습니다.
  ) {
    // 버튼 아이콘의 적절한 크기를 itemHeight에 맞춰 조정합니다.
    final double iconSize =
        parentItemHeight * 0.7; // 예: 24 * 0.7 = 16.8 (24px 높이 기준)

    return SizedBox(
      // ✅ PopupMenuButton을 SizedBox로 감싸서 높이를 제한
      height: parentItemHeight, // 부모 항목 높이와 동일하게 설정
      width: parentItemHeight, // 버튼의 터치 영역을 정사각형으로 맞춤
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
        ), // ✅ 아이콘 크기 조정
        tooltip: '더보기',
        padding: EdgeInsets.zero, // ✅ 버튼 내부 패딩 제거
        splashRadius: 16, // ✅ 물결 효과 반경 줄임 (아이콘 크기에 맞춰)
      ),
    );
  }
}
