// lib/layout/right_sidebar/history_sidebar.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../viewmodels/history_viewmodel.dart';

class HistorySidebar extends StatefulWidget {
  const HistorySidebar({Key? key}) : super(key: key);

  @override
  State<HistorySidebar> createState() => _HistorySidebarState();
}

class _HistorySidebarState extends State<HistorySidebar> {
  final TextEditingController _historySearchController =
      TextEditingController();
  DateFilterPeriod? _selectedPeriod; // '전체'는 null로 표현
  Set<String> _selectedDomains = {};
  Set<String> _selectedTags = {};

  final List<String> _popularTags = [
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
  final List<String> _famousDomains = [
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
    _loadCustomFilters();
    _historySearchController.addListener(_onHistorySearchChanged);
  }

  @override
  void dispose() {
    _historySearchController.removeListener(_onHistorySearchChanged);
    _historySearchController.dispose();
    _domainInputController.dispose();
    _tagInputController.dispose();
    _domainFocusNode.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCustomFilters() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _customDomains = prefs.getStringList('custom_domains') ?? [];
        _customTags = prefs.getStringList('custom_tags') ?? [];
      });
    }
  }

  Future<void> _saveCustomFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_domains', _customDomains);
    await prefs.setStringList('custom_tags', _customTags);
  }

  void _onHistorySearchChanged() {
    final historyViewModel = Provider.of<HistoryViewModel>(
      context,
      listen: false,
    );
    historyViewModel.applyFilters(
      query: _historySearchController.text,
      period: _selectedPeriod,
      domains: _selectedDomains,
      tags: _selectedTags,
      sortOrder: _sortOrder,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '검색...',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: theme.scaffoldBackgroundColor,
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
                        _selectedPeriod = null; // 초기화 시 null로 설정
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
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildFilterSection(
                  title: '날짜 범위',
                  children: [
                    // ✨ [추가] '전체' 옵션
                    _buildPeriodRadio(null, '전체'),
                    _buildPeriodRadio(DateFilterPeriod.today, '오늘'),
                    _buildPeriodRadio(DateFilterPeriod.thisWeek, '이번 주'),
                    _buildPeriodRadio(DateFilterPeriod.thisMonth, '이번 달'),
                    _buildPeriodRadio(DateFilterPeriod.thisYear, '올해'),
                    const Divider(height: 16),
                    _buildSortOrderRadio(SortOrder.latest, '최신순'),
                    _buildSortOrderRadio(SortOrder.oldest, '과거순'),
                  ],
                ),
                const Divider(height: 16),
                _buildFilterSection(
                  title: '도메인',
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
                    if (_customDomains.isNotEmpty) const Divider(height: 16),
                    ..._customDomains
                        .map(
                          (domain) =>
                              _buildDomainCheckbox(domain, isCustom: true),
                        )
                        .toList(),
                  ],
                ),
                const Divider(height: 16),
                _buildFilterSection(
                  title: '태그',
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
                    if (_customTags.isNotEmpty) const Divider(height: 16),
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

  Widget _buildFilterSection({
    required String title,
    required List<Widget> children,
    VoidCallback? onAdd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.grey.shade600,
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
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  // ✨ [수정] 위젯 이름 변경 및 파라미터 타입 nullable로 변경
  Widget _buildPeriodRadio(DateFilterPeriod? period, String title) {
    final historyViewModel = context.read<HistoryViewModel>();
    return InkWell(
      onTap: () {
        setState(() => _selectedPeriod = period);
        historyViewModel.applyFilters(
          period: period,
          domains: _selectedDomains,
          tags: _selectedTags,
          sortOrder: _sortOrder,
          isPeriodChange: true,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: Radio<DateFilterPeriod?>(
                // ✨ [수정] 타입 nullable
                visualDensity: VisualDensity.compact,
                value: period,
                groupValue: _selectedPeriod,
                onChanged: (DateFilterPeriod? value) {
                  setState(() => _selectedPeriod = value);
                  historyViewModel.applyFilters(
                    period: value,
                    domains: _selectedDomains,
                    tags: _selectedTags,
                    sortOrder: _sortOrder,
                    isPeriodChange: true,
                  );
                },
                activeColor: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 12)),
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
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: Radio<SortOrder>(
                visualDensity: VisualDensity.compact,
                value: order,
                groupValue: _sortOrder,
                onChanged: (SortOrder? value) {
                  if (value != null) {
                    setState(() => _sortOrder = value);
                    historyViewModel.applyFilters(sortOrder: value);
                  }
                },
                activeColor: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 12)),
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
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: Checkbox(
                  visualDensity: VisualDensity.compact,
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
                  activeColor: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(domain, style: const TextStyle(fontSize: 12)),
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
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: Checkbox(
                  visualDensity: VisualDensity.compact,
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
                  activeColor: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(tag, style: const TextStyle(fontSize: 12))),
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
}
