// lib/layout/right_sidebar_content.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/file_system_entry.dart';
import '../providers/file_system_provider.dart';
import '../widgets/expandable_folder_tile.dart';
import '../layout/bottom_section_controller.dart';
import '../widgets/note_outline_view.dart';
import '../widgets/scratchpad_view.dart';
import '../features/page_type.dart';
import '../widgets/custom_popup_menu.dart';
import '../viewmodels/calendar_viewmodel.dart';
import '../viewmodels/calendar_sidebar_viewmodel.dart';
import '../viewmodels/history_viewmodel.dart';

class RightSidebarContent extends StatefulWidget {
  final PageType activePage;
  final bool isLoading;
  final List<FileSystemEntry> fileSystemEntries;
  final Function(FileSystemEntry) onEntryTap;
  final VoidCallback onRefresh;
  final Function(FileSystemEntry) onRenameEntry;
  final Function(FileSystemEntry) onDeleteEntry;
  final bool sidebarIsExpanded;

  const RightSidebarContent({
    Key? key,
    required this.activePage,
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

  String? _editingPath;
  bool _isCreatingNew = false;
  bool _isCreatingFolder = false;
  String? _creationParentPath;
  final TextEditingController _editingController = TextEditingController();
  final FocusNode _editingFocusNode = FocusNode();

  final TextEditingController _historySearchController =
      TextEditingController();
  DateFilterPeriod? _selectedPeriod;
  Set<String> _selectedDomains = {};
  Set<String> _selectedTags = {};
  bool _isTagFilterExpanded = false;

  List<String> _popularTags = [
    '공부',
    '업무',
    '뉴스',
    '기술',
    '쇼핑',
    '여행',
    '요리',
    '건강',
    '영화',
    '책',
  ];
  List<String> _famousDomains = [
    'google.com',
    'youtube.com',
    'facebook.com',
    'instagram.com',
    'wikipedia.org',
    'x.com',
    'reddit.com',
    'amazon.com',
    'naver.com',
    'bing.com',
  ];
  List<String> _customTags = [];
  List<String> _customDomains = [];

  bool _isDateFilterExpanded = false;
  bool _isDomainFilterExpanded = false;

  bool _isAddingDomain = false;
  bool _isAddingTag = false;
  final TextEditingController _domainInputController = TextEditingController();
  final TextEditingController _tagInputController = TextEditingController();
  final FocusNode _domainFocusNode = FocusNode();
  final FocusNode _tagFocusNode = FocusNode();

  SortOrder _sortOrder = SortOrder.latest;

  String? _hoveredDomain;
  String? _hoveredTag;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCustomFilters();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomSectionController = Provider.of<BottomSectionController>(
        context,
        listen: false,
      );
      _bottomSectionController.addListener(_onControllerUpdate);
      _tabController.index = _bottomSectionController.activeRightSidebarTab;
      _historySearchController.addListener(_onHistorySearchChanged);
    });
  }

  Future<void> _loadCustomFilters() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customDomains = prefs.getStringList('custom_domains') ?? [];
      _customTags = prefs.getStringList('custom_tags') ?? [];
    });
  }

  Future<void> _saveCustomFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_domains', _customDomains);
    await prefs.setStringList('custom_tags', _customTags);
  }

  void _onHistorySearchChanged() {
    final historyViewModel = context.read<HistoryViewModel>();
    historyViewModel.applyFilters(
      query: _historySearchController.text,
      period: _selectedPeriod,
      domains: _selectedDomains,
      tags: _selectedTags,
      sortOrder: _sortOrder,
    );
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
    _editingController.dispose();
    _editingFocusNode.dispose();
    _historySearchController.removeListener(_onHistorySearchChanged);
    _historySearchController.dispose();
    _domainInputController.dispose();
    _tagInputController.dispose();
    _domainFocusNode.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  void _startCreatingNewFile() {
    if (_editingPath != null) return;
    final provider = context.read<FileSystemProvider>();
    setState(() {
      _isCreatingNew = true;
      _isCreatingFolder = false;
      _editingPath = 'new_file';
      _creationParentPath = provider.selectedFolderPath;
      _editingController.clear();
    });
    _editingFocusNode.requestFocus();
  }

  void _startCreatingNewFolder() {
    if (_editingPath != null) return;
    final provider = context.read<FileSystemProvider>();
    setState(() {
      _isCreatingNew = true;
      _isCreatingFolder = true;
      _editingPath = 'new_folder';
      _creationParentPath = provider.selectedFolderPath;
      _editingController.clear();
    });
    _editingFocusNode.requestFocus();
  }

  void _startRenaming(FileSystemEntry entry) {
    if (_editingPath != null) return;
    setState(() {
      _isCreatingNew = false;
      _editingPath = entry.path;
      _editingController.text =
          entry.isDirectory
              ? entry.name
              : p.basenameWithoutExtension(entry.name);
    });
    _editingFocusNode.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editingPath = null;
      _isCreatingNew = false;
      _creationParentPath = null;
      _editingController.clear();
    });
  }

  void _submitEdit() {
    final name = _editingController.text.trim();
    final provider = context.read<FileSystemProvider>();

    if (_isCreatingNew) {
      if (name.isNotEmpty) {
        if (_isCreatingFolder) {
          provider.createNewFolder(
            context,
            name,
            parentPath: _creationParentPath,
          );
        } else {
          provider.createNewFile(
            context,
            name,
            parentPath: _creationParentPath,
          );
        }
      }
    } else if (_editingPath != null) {
      FileSystemEntry? findEntryByPath(
        List<FileSystemEntry> entries,
        String path,
      ) {
        for (var entry in entries) {
          if (entry.path == path) return entry;
          if (entry.isDirectory && entry.children != null) {
            final found = findEntryByPath(entry.children!, path);
            if (found != null) return found;
          }
        }
        return null;
      }

      final entryToRename = findEntryByPath(
        widget.fileSystemEntries,
        _editingPath!,
      );
      if (entryToRename != null) {
        final currentName =
            entryToRename.isDirectory
                ? entryToRename.name
                : p.basenameWithoutExtension(entryToRename.name);

        if (name.isNotEmpty && name != currentName) {
          final newFullName = entryToRename.isDirectory ? name : '$name.md';
          provider.renameEntry(context, entryToRename, newFullName);
        }
      }
    }
    _cancelEditing();
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    FileSystemEntry entry,
  ) {
    final fileSystemProvider = context.read<FileSystemProvider>();

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: <PopupMenuEntry<String>>[
        CompactPopupMenuItem<String>(
          value: 'pin',
          child: Text(entry.isPinned ? '고정 해제' : '고정하기'),
        ),
        CompactPopupMenuItem<String>(
          value: 'rename',
          child: const Text('이름 변경'),
        ),
        CompactPopupMenuItem<String>(
          value: 'delete',
          child: Text('삭제', style: TextStyle(color: Colors.redAccent.shade100)),
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      elevation: 4.0,
      color: Theme.of(context).cardColor,
    ).then((String? value) {
      if (value == 'rename') {
        _startRenaming(entry);
      } else if (value == 'delete') {
        widget.onDeleteEntry(entry);
      } else if (value == 'pin') {
        fileSystemProvider.togglePinStatus(entry);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.activePage) {
      case PageType.home:
        return _buildMemoSidebar(context);
      case PageType.history:
        return _buildHistorySidebar(context);
      case PageType.graph:
        return _buildGraphSidebar(context);
      case PageType.calendar:
        return _buildCalendarSidebar(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCalendarSidebar(BuildContext context) {
    final theme = Theme.of(context);
    final calendarViewModel = context.watch<CalendarViewModel>();

    return Column(
      children: [
        // ✨ [수정] InkWell을 제거하여 클릭 기능을 없애고, 아이콘도 제거합니다.
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              DateFormat(
                'yyyy년 MM월 dd일 (E)',
                'ko_KR',
              ).format(calendarViewModel.selectedDay),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ),
        const Expanded(child: CalendarSidebarView()),
      ],
    );
  }

  Widget _buildHistorySidebar(BuildContext context) {
    final historyViewModel = context.watch<HistoryViewModel>();
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "필터",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _historySearchController,
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '검색...',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.primaryColor,
                        width: 2,
                      ),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                  ),
                ),
                const SizedBox(height: 5.6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('필터 초기화'),
                    onPressed: () {
                      setState(() {
                        _historySearchController.clear();
                        _selectedPeriod = null;
                        _selectedDomains.clear();
                        _selectedTags.clear();
                        _sortOrder = SortOrder.latest;
                      });
                      historyViewModel.applyFilters(
                        query: '',
                        period: null,
                        domains: {},
                        tags: {},
                        sortOrder: SortOrder.latest,
                        isPeriodChange: true,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0078D4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _buildCompactExpansionTile(
                  title: '날짜 범위',
                  isExpanded: _isDateFilterExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() => _isDateFilterExpanded = expanded);
                  },
                  children: [
                    _buildPeriodCheckbox(DateFilterPeriod.today, '오늘'),
                    _buildPeriodCheckbox(DateFilterPeriod.thisWeek, '이번 주'),
                    _buildPeriodCheckbox(DateFilterPeriod.thisMonth, '이번 달'),
                    _buildPeriodCheckbox(DateFilterPeriod.thisYear, '올해'),
                    const Divider(),
                    _buildSortOrderRadio(SortOrder.latest, '최신순'),
                    _buildSortOrderRadio(SortOrder.oldest, '과거순'),
                  ],
                ),
                const SizedBox(height: 4),
                _buildCompactExpansionTile(
                  title: '도메인',
                  isExpanded: _isDomainFilterExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() => _isDomainFilterExpanded = expanded);
                  },
                  onAdd: () {
                    setState(() => _isAddingDomain = !_isAddingDomain);
                    if (_isAddingDomain) {
                      _domainFocusNode.requestFocus();
                    }
                  },
                  children: [
                    if (_isAddingDomain) _buildDomainInputField(),
                    ..._famousDomains
                        .map(
                          (domain) =>
                              _buildDomainCheckbox(domain, isCustom: false),
                        )
                        .toList(),
                    if (_customDomains.isNotEmpty) const Divider(),
                    ..._customDomains
                        .map(
                          (domain) =>
                              _buildDomainCheckbox(domain, isCustom: true),
                        )
                        .toList(),
                  ],
                ),
                const SizedBox(height: 4),
                _buildCompactExpansionTile(
                  title: '태그',
                  isExpanded: _isTagFilterExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() => _isTagFilterExpanded = expanded);
                  },
                  onAdd: () {
                    setState(() => _isAddingTag = !_isAddingTag);
                    if (_isAddingTag) {
                      _tagFocusNode.requestFocus();
                    }
                  },
                  children: [
                    if (_isAddingTag) _buildTagInputField(),
                    ..._popularTags
                        .map((tag) => _buildTagCheckbox(tag, isCustom: false))
                        .toList(),
                    if (_customTags.isNotEmpty) const Divider(),
                    ..._customTags
                        .map((tag) => _buildTagCheckbox(tag, isCustom: true))
                        .toList(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactExpansionTile({
    required String title,
    required bool isExpanded,
    required ValueChanged<bool> onExpansionChanged,
    required List<Widget> children,
    VoidCallback? onAdd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onExpansionChanged(!isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 20,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (onAdd != null)
                  IconButton(
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: onAdd,
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child:
              isExpanded
                  ? Padding(
                    padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildPeriodCheckbox(DateFilterPeriod period, String title) {
    final historyViewModel = context.read<HistoryViewModel>();
    return InkWell(
      onTap: () {
        final newPeriod = (_selectedPeriod == period) ? null : period;
        setState(() {
          _selectedPeriod = newPeriod;
        });
        historyViewModel.applyFilters(
          period: newPeriod,
          domains: _selectedDomains,
          tags: _selectedTags,
          sortOrder: _sortOrder,
          isPeriodChange: true,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 0.0),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: Checkbox(
                value: _selectedPeriod == period,
                onChanged: (bool? value) {
                  final newPeriod = (value == true) ? period : null;
                  setState(() {
                    _selectedPeriod = newPeriod;
                  });
                  historyViewModel.applyFilters(
                    period: newPeriod,
                    domains: _selectedDomains,
                    tags: _selectedTags,
                    sortOrder: _sortOrder,
                    isPeriodChange: true,
                  );
                },
                activeColor: const Color(0xFF0078D4),
              ),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOrderRadio(SortOrder order, String title) {
    final historyViewModel = context.read<HistoryViewModel>();
    return InkWell(
      onTap: () {
        setState(() => _sortOrder = order);
        historyViewModel.applyFilters(sortOrder: order);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 0.0),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: Radio<SortOrder>(
                value: order,
                groupValue: _sortOrder,
                onChanged: (SortOrder? value) {
                  if (value != null) {
                    setState(() => _sortOrder = value);
                    historyViewModel.applyFilters(sortOrder: value);
                  }
                },
                activeColor: const Color(0xFF0078D4),
              ),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildDomainCheckbox(String domain, {required bool isCustom}) {
    final historyViewModel = context.read<HistoryViewModel>();
    final bool isSelected = _selectedDomains.contains(domain);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredDomain = domain),
      onExit: (_) => setState(() => _hoveredDomain = null),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedDomains.remove(domain);
            } else {
              _selectedDomains.add(domain);
            }
          });
          historyViewModel.applyFilters(
            period: _selectedPeriod,
            domains: _selectedDomains,
            tags: _selectedTags,
            sortOrder: _sortOrder,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 0.0),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedDomains.add(domain);
                      } else {
                        _selectedDomains.remove(domain);
                      }
                    });
                    historyViewModel.applyFilters(
                      period: _selectedPeriod,
                      domains: _selectedDomains,
                      tags: _selectedTags,
                      sortOrder: _sortOrder,
                    );
                  },
                  activeColor: const Color(0xFF0078D4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(domain, style: const TextStyle(fontSize: 14)),
              ),
              if (isCustom && _hoveredDomain == domain)
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      _customDomains.remove(domain);
                      _selectedDomains.remove(domain);
                    });
                    _saveCustomFilters();
                    historyViewModel.applyFilters(domains: _selectedDomains);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagCheckbox(String tag, {required bool isCustom}) {
    final historyViewModel = context.read<HistoryViewModel>();
    final bool isSelected = _selectedTags.contains(tag);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredTag = tag),
      onExit: (_) => setState(() => _hoveredTag = null),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedTags.remove(tag);
            } else {
              _selectedTags.add(tag);
            }
          });
          historyViewModel.applyFilters(
            period: _selectedPeriod,
            domains: _selectedDomains,
            tags: _selectedTags,
            sortOrder: _sortOrder,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 0.0),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedTags.add(tag);
                      } else {
                        _selectedTags.remove(tag);
                      }
                    });
                    historyViewModel.applyFilters(
                      period: _selectedPeriod,
                      domains: _selectedDomains,
                      tags: _selectedTags,
                      sortOrder: _sortOrder,
                    );
                  },
                  activeColor: const Color(0xFF0078D4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(tag, style: const TextStyle(fontSize: 14))),
              if (isCustom && _hoveredTag == tag)
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      _customTags.remove(tag);
                      _selectedTags.remove(tag);
                    });
                    _saveCustomFilters();
                    historyViewModel.applyFilters(tags: _selectedTags);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDomainInputField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: TextField(
        controller: _domainInputController,
        focusNode: _domainFocusNode,
        decoration: const InputDecoration(
          hintText: 'e.g., example.com',
          isDense: true,
        ),
        onSubmitted: (value) {
          final domain = value.trim().toLowerCase();
          final RegExp domainRegex = RegExp(r'^[a-zA-Z0-9-]+\.[a-zA-Z]{2,}$');

          if (domain.isNotEmpty && domainRegex.hasMatch(domain)) {
            if (!_famousDomains.contains(domain) &&
                !_customDomains.contains(domain)) {
              setState(() {
                _customDomains.add(domain);
                _isAddingDomain = false;
                _domainInputController.clear();
              });
              _saveCustomFilters();
            }
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('올바른 도메인 형식이 아닙니다.')));
          }
        },
      ),
    );
  }

  Widget _buildTagInputField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: TextField(
        controller: _tagInputController,
        focusNode: _tagFocusNode,
        decoration: const InputDecoration(
          hintText: '새 태그 추가...',
          isDense: true,
        ),
        onSubmitted: (value) {
          final tag = value.trim();
          if (tag.isNotEmpty) {
            if (!_popularTags.contains(tag) && !_customTags.contains(tag)) {
              setState(() {
                _customTags.add(tag);
                _isAddingTag = false;
                _tagInputController.clear();
              });
              _saveCustomFilters();
            }
          }
        },
      ),
    );
  }

  Widget _buildMemoSidebar(BuildContext context) {
    // ... (기존과 동일)
    final bottomCtrl = Provider.of<BottomSectionController>(context);

    return Column(
      children: [
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            tabAlignment: TabAlignment.fill,
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Theme.of(context).primaryColor,
            indicatorWeight: 2.5,
            onTap: (index) {
              bottomCtrl.setActiveTab(index);
            },
            tabs: const [
              Tab(
                icon: Icon(Icons.folder_outlined, size: 16),
                iconMargin: EdgeInsets.zero,
              ),
              Tab(
                icon: Icon(Icons.format_list_bulleted, size: 16),
                iconMargin: EdgeInsets.zero,
              ),
              Tab(
                icon: Icon(Icons.edit_note, size: 16),
                iconMargin: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildFileListView(),
              const NoteOutlineView(),
              const ScratchpadView(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGraphSidebar(BuildContext context) {
    // ... (기존과 동일)
    return const Center(
      child: Text('그래프 정보 표시 영역', style: TextStyle(color: Colors.grey)),
    );
  }

  Widget _buildFileListView() {
    // ... (기존과 동일)
    List<FileSystemEntry> getAllPinnedEntries(List<FileSystemEntry> entries) {
      final List<FileSystemEntry> pinned = [];
      final Set<String> seenPaths = {};
      void findPinnedRecursive(List<FileSystemEntry> currentEntries) {
        for (final entry in currentEntries) {
          if (entry.isPinned) {
            if (seenPaths.add(entry.path)) pinned.add(entry);
          }
          if (entry.isDirectory && entry.children != null) {
            findPinnedRecursive(entry.children!);
          }
        }
      }

      findPinnedRecursive(entries);
      return pinned;
    }

    final fileSystemProvider = context.read<FileSystemProvider>();
    final pinnedEntries = getAllPinnedEntries(widget.fileSystemEntries);
    final regularEntries = widget.fileSystemEntries;

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
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.note_add_outlined,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    tooltip: "새 파일",
                    onPressed: widget.isLoading ? null : _startCreatingNewFile,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tight(const Size(28, 28)),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.create_new_folder_outlined,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    tooltip: "새 폴더",
                    onPressed:
                        widget.isLoading ? null : _startCreatingNewFolder,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tight(const Size(28, 28)),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (widget.fileSystemEntries.isEmpty && !_isCreatingNew)
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
            child: DragTarget<FileSystemEntry>(
              onWillAccept: (entry) => entry != null,
              onLeave: (entry) {},
              onAccept: (entry) async {
                final rootPath =
                    await fileSystemProvider.getOrCreateNoteFolderPath();
                fileSystemProvider.moveEntry(
                  context,
                  entryToMove: entry,
                  newParentPath: rootPath,
                );
              },
              builder: (context, candidateData, rejectedData) {
                final isDragOverRoot = candidateData.isNotEmpty;
                return Container(
                  color:
                      isDragOverRoot
                          ? Theme.of(context).primaryColor.withOpacity(0.1)
                          : Colors.transparent,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 4.0,
                    ),
                    children: [
                      if (_isCreatingNew && _creationParentPath == null)
                        _buildInlineEditingItem(
                          isFolder: _isCreatingFolder,
                          indentLevel: 0,
                          isLast: true,
                          parentIsLast: [],
                        ),
                      if (pinnedEntries.isNotEmpty) ...[
                        _buildSectionHeader("고정된 메모"),
                        for (int i = 0; i < pinnedEntries.length; i++)
                          _buildFileSystemEntry(
                            context,
                            pinnedEntries[i],
                            0,
                            isLast: i == pinnedEntries.length - 1,
                            parentIsLast: [],
                          ),
                        const Divider(height: 24, thickness: 1),
                      ],
                      if (regularEntries.isNotEmpty) ...[
                        if (pinnedEntries.isNotEmpty) _buildSectionHeader("메모"),
                        for (int i = 0; i < regularEntries.length; i++)
                          _buildFileSystemEntry(
                            context,
                            regularEntries[i],
                            0,
                            isLast: i == regularEntries.length - 1,
                            parentIsLast: [],
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 4.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _buildInlineEditingItem({
    required bool isFolder,
    required int indentLevel,
    required bool isLast,
    required List<bool> parentIsLast,
  }) {
    final double itemHeight = 24.0;
    final double indentPerLevel = 15.0;
    return Row(
      children: [
        CustomPaint(
          size: Size(indentLevel * indentPerLevel, itemHeight),
          painter: _TreeLinePainter(
            indentLevel: indentLevel,
            isLast: isLast,
            parentIsLast: parentIsLast,
            color: Colors.grey.shade500,
          ),
        ),
        Icon(
          isFolder ? Icons.folder_outlined : Icons.description_outlined,
          size: 16,
          color: Colors.grey.shade500,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: _editingController,
            focusNode: _editingFocusNode,
            autofocus: true,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.only(bottom: 8),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _submitEdit(),
            onTapOutside: (_) => _submitEdit(),
          ),
        ),
      ],
    );
  }

  Widget _buildFileSystemEntry(
    BuildContext context,
    FileSystemEntry entry,
    int indentLevel, {
    required bool isLast,
    required List<bool> parentIsLast,
  }) {
    if (_editingPath == entry.path) {
      return _buildInlineEditingItem(
        isFolder: entry.isDirectory,
        indentLevel: indentLevel,
        isLast: isLast,
        parentIsLast: parentIsLast,
      );
    }

    final fileSystemProvider = context.watch<FileSystemProvider>();

    Widget tile;
    if (entry.isDirectory) {
      final isSelected = fileSystemProvider.selectedFolderPath == entry.path;

      tile = DragTarget<FileSystemEntry>(
        onWillAccept: (data) {
          if (data == null ||
              data.path == entry.path ||
              p.isWithin(entry.path, data.path)) {
            return false;
          }
          return true;
        },
        onLeave: (data) {},
        onAccept: (data) {
          fileSystemProvider.moveEntry(
            context,
            entryToMove: data,
            newParentPath: entry.path,
          );
        },
        builder: (context, candidateData, rejectedData) {
          final isDragOver = candidateData.isNotEmpty;
          return ExpandableFolderTile(
            key: PageStorageKey(entry.path),
            folderIcon: Icon(
              Icons.folder,
              size: 16,
              color: Colors.blueGrey.shade600,
            ),
            title: Text(
              entry.name,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Work Sans',
              ),
              overflow: TextOverflow.ellipsis,
            ),
            onSelect: () => fileSystemProvider.selectFolder(entry.path),
            isSelected: isSelected,
            isInitiallyExpanded: fileSystemProvider.expandedFolderPaths
                .contains(entry.path),
            onExpansionChanged:
                (isExpanded) => fileSystemProvider.setFolderExpanded(
                  entry.path,
                  isExpanded,
                ),
            backgroundColor:
                isDragOver
                    ? Theme.of(context).primaryColor.withOpacity(0.1)
                    : null,
            onSecondaryTapUp:
                (details) =>
                    _showContextMenu(context, details.globalPosition, entry),
            children: [
              if (_isCreatingNew && _creationParentPath == entry.path)
                _buildInlineEditingItem(
                  isFolder: _isCreatingFolder,
                  indentLevel: indentLevel + 1,
                  isLast: true,
                  parentIsLast: [...parentIsLast, isLast],
                ),
              for (int i = 0; i < entry.children!.length; i++)
                _buildFileSystemEntry(
                  context,
                  entry.children![i],
                  indentLevel + 1,
                  isLast: i == entry.children!.length - 1,
                  parentIsLast: [...parentIsLast, isLast],
                ),
            ],
          );
        },
      );
    } else {
      tile = GestureDetector(
        onSecondaryTapUp:
            (details) =>
                _showContextMenu(context, details.globalPosition, entry),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.onEntryTap(entry),
            borderRadius: BorderRadius.zero,
            hoverColor: Colors.grey[200],
            child: SizedBox(
              height: 24.0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p.basenameWithoutExtension(entry.name),
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        fontFamily: 'Work Sans',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: Icon(
                        Icons.push_pin,
                        size: 12,
                        color: Colors.blueGrey.shade400,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomPaint(
          size: Size(indentLevel * 15.0, 24.0),
          painter: _TreeLinePainter(
            indentLevel: indentLevel,
            isLast: isLast,
            parentIsLast: parentIsLast,
            color: Colors.grey.shade500,
          ),
        ),
        Expanded(
          child: Draggable<FileSystemEntry>(
            data: entry,
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      entry.isDirectory ? Icons.folder : Icons.description,
                      size: 14,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: tile),
            onDragStarted: () {
              if (entry.isDirectory) {
                fileSystemProvider.setFolderExpanded(entry.path, false);
              }
            },
            child: tile,
          ),
        ),
      ],
    );
  }
}

class _TreeLinePainter extends CustomPainter {
  final int indentLevel;
  final bool isLast;
  final List<bool> parentIsLast;
  final Color color;
  final double strokeWidth;
  final double indentSpace;

  _TreeLinePainter({
    required this.indentLevel,
    required this.isLast,
    required this.parentIsLast,
    this.color = Colors.grey,
    this.strokeWidth = 1.0,
    this.indentSpace = 15.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth;

    for (int i = 0; i < parentIsLast.length; i++) {
      if (!parentIsLast[i]) {
        final dx = (i * indentSpace) + (indentSpace / 2);
        canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      }
    }

    if (indentLevel > 0) {
      final double dx = ((indentLevel - 1) * indentSpace) + (indentSpace / 2);
      final double dy = size.height / 2;

      canvas.drawLine(Offset(dx, dy), Offset(dx + indentSpace / 2, dy), paint);

      if (isLast) {
        canvas.drawLine(Offset(dx, 0), Offset(dx, dy), paint);
      } else {
        canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CalendarSidebarView extends StatefulWidget {
  const CalendarSidebarView({Key? key}) : super(key: key);

  @override
  State<CalendarSidebarView> createState() => _CalendarSidebarViewState();
}

class _CalendarSidebarViewState extends State<CalendarSidebarView> {
  late CalendarViewModel _calendarViewModel;
  late CalendarSidebarViewModel _sidebarViewModel;
  DateTime? _lastFetchedDay;

  @override
  void initState() {
    super.initState();
    _calendarViewModel = context.read<CalendarViewModel>();
    _sidebarViewModel = context.read<CalendarSidebarViewModel>();
    _calendarViewModel.addListener(_onSelectedDayChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchNotesForSelectedDayIfNeeded();
    });
  }

  void _onSelectedDayChange() {
    _fetchNotesForSelectedDayIfNeeded();
  }

  void _fetchNotesForSelectedDayIfNeeded() {
    final currentSelectedDay = _calendarViewModel.selectedDay;
    if (_lastFetchedDay != currentSelectedDay) {
      _lastFetchedDay = currentSelectedDay;
      _sidebarViewModel.fetchModifiedNotes(currentSelectedDay);
    }
  }

  @override
  void dispose() {
    _calendarViewModel.removeListener(_onSelectedDayChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sidebarViewModel = context.watch<CalendarSidebarViewModel>();

    // ✨ [수정] 날짜 중복 표시를 제거하고, 패딩을 조정합니다.
    if (sidebarViewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (sidebarViewModel.modifiedNotes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            '이 날짜에 수정된 노트가 없습니다.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return _buildNotesList(sidebarViewModel);
  }

  Widget _buildNotesList(CalendarSidebarViewModel sidebarViewModel) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
      itemCount: sidebarViewModel.modifiedNotes.length,
      itemBuilder: (context, index) {
        final note = sidebarViewModel.modifiedNotes[index];
        final formattedTime =
            note.modifiedTime != null
                ? DateFormat('HH:mm:ss').format(note.modifiedTime!)
                : '';

        return ListTile(
          leading: const Icon(Icons.description_outlined, size: 20),
          title: Text(
            p.basenameWithoutExtension(note.name),
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '수정된 시간: $formattedTime',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          dense: true,
          onTap: () {
            context.read<FileSystemProvider>().setSelectedFileForMeetingScreen(
              note,
            );
          },
        );
      },
    );
  }
}
