// lib/layout/right_sidebar_content.dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../model/file_system_entry.dart';
import '../widgets/expandable_folder_tile.dart';
import '../layout/bottom_section_controller.dart';
import '../widgets/ai_summary_widget.dart';

class RightSidebarContent extends StatefulWidget {
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
  State<RightSidebarContent> createState() => _RightSidebarContentState();
}

class _RightSidebarContentState extends State<RightSidebarContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late BottomSectionController _bottomSectionController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomSectionController = Provider.of<BottomSectionController>(
        context,
        listen: false,
      );
      _bottomSectionController.addListener(_onControllerUpdate);
      _tabController.index = _bottomSectionController.activeRightSidebarTab;
    });
  }

  void _onControllerUpdate() {
    if (_tabController.index !=
        _bottomSectionController.activeRightSidebarTab) {
      _tabController.animateTo(_bottomSectionController.activeRightSidebarTab);
    }
  }

  @override
  void dispose() {
    _bottomSectionController.removeListener(_onControllerUpdate);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomCtrl = Provider.of<BottomSectionController>(context);

    return Column(
      children: [
        Container(
          height: 40,
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Theme.of(context).primaryColor,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Theme.of(context).primaryColor,
                indicatorWeight: 2.5,
                tabAlignment: TabAlignment.start,
                onTap: (index) {
                  bottomCtrl.setActiveTab(index);
                },
                tabs: const [
                  Tab(
                    icon: Icon(Icons.folder_outlined, size: 20),
                    iconMargin: EdgeInsets.zero,
                  ),
                  Tab(
                    icon: Icon(Icons.auto_awesome_outlined, size: 20),
                    iconMargin: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildFileListView(),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: AiSummaryWidget(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 0.0),
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
                onPressed: widget.isLoading ? null : widget.onRefresh,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tight(const Size(28, 28)),
              ),
            ],
          ),
        ),
        // ✨ [수정] "저장된 메모"와 파일 목록 사이의 불필요한 여백을 제거했습니다.
        if (widget.isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (widget.fileSystemEntries.isEmpty)
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
              padding: const EdgeInsets.symmetric(
                horizontal: 4.0,
                vertical: 4.0,
              ),
              itemCount: widget.fileSystemEntries.length,
              itemBuilder: (context, index) {
                final entry = widget.fileSystemEntries[index];
                return _buildFileSystemEntry(
                  context,
                  entry,
                  widget.onEntryTap,
                  widget.onRenameEntry,
                  widget.onDeleteEntry,
                  0,
                  widget.sidebarIsExpanded,
                );
              },
            ),
          ),
      ],
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
    final double indentPerLevel = sidebarIsExpanded ? 15.0 : 0.0;
    final double effectivePaddingLeft = (indentLevel * indentPerLevel);

    final Color defaultTextColor = Colors.grey.shade800;
    final Color fileIconColor = Colors.grey.shade500;
    final Color folderIconColor = Colors.blueGrey.shade600;

    if (entry.isDirectory) {
      return ExpandableFolderTile(
        key: PageStorageKey(entry.path),
        itemHeight: itemHeight,
        arrowColor: Colors.grey,
        folderIcon: Padding(
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
      final double totalLeftFixedSpaceForFile =
          (sidebarIsExpanded ? 20.0 + 4.0 : 0.0 + 4.0);
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
                left: effectivePaddingLeft + totalLeftFixedSpaceForFile,
                right: 8.0,
              ),
              child: ClipRect(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: fileIconColor,
                    ),
                    const SizedBox(width: 4),
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
