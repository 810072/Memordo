// lib/viewmodels/graph_viewmodel.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:watcher/watcher.dart';

import '../utils/ai_service.dart' as ai_service;
import '../widgets/force_graph_widget.dart';
import '../providers/status_bar_provider.dart';

enum GraphFilterMode { all, connected, isolated }

class UserGraphNodeInfo {
  final String fileName;
  final List<String> outgoingLinks;
  final Set<String> incomingLinks;

  UserGraphNodeInfo({required this.fileName, required this.outgoingLinks})
    : incomingLinks = {};

  int get totalLinks => outgoingLinks.length + incomingLinks.length;
}

class GraphViewModel with ChangeNotifier {
  bool _isLoading = false;
  String _statusMessage = '그래프를 생성하려면 우측 상단의 버튼을 눌러주세요.';
  bool _isAiGraphView = false;

  List<GraphNode> _allNodes = [];
  List<GraphLink> _allLinks = [];
  List<GraphNode> _filteredNodes = [];
  List<GraphLink> _filteredLinks = [];

  GraphFilterMode _filterMode = GraphFilterMode.all;
  GraphFilterMode get filterMode => _filterMode;

  final Map<String, UserGraphNodeInfo> _userGraphData = {};
  Map<String, Map<String, double>> _nodePositions = {};
  Timer? _saveDebounce;

  // ✨ [추가] FileWatcher 관련
  DirectoryWatcher? _watcher;
  StreamSubscription? _watcherSubscription;
  bool _isWatching = false;
  Timer? _processingDebounce;
  final Set<String> _pendingChanges = {};

  bool get isLoading => _isLoading;
  String get statusMessage => _statusMessage;
  bool get isAiGraphView => _isAiGraphView;
  List<GraphNode> get nodes => _filteredNodes;
  List<GraphLink> get links => _filteredLinks;
  Map<String, Map<String, double>> get nodePositions => _nodePositions;

  int getNodeLinkCount(String nodeId) {
    if (_isAiGraphView) {
      return _allLinks
          .where((l) => l.sourceId == nodeId || l.targetId == nodeId)
          .length;
    } else {
      final key = _userGraphData.keys.firstWhere(
        (k) => k.toLowerCase() == nodeId.toLowerCase(),
        orElse: () => '',
      );
      return _userGraphData[key]?.totalLinks ?? 0;
    }
  }

  double getNodeSize(GraphNode node) {
    final linkCount = getNodeLinkCount(node.id);
    return 10.0 + (linkCount * 1.5).clamp(0.0, 10.0);
  }

  void setFilterMode(GraphFilterMode mode) {
    if (_filterMode == mode) return;
    _filterMode = mode;
    _applyFilter();
  }

  void _applyFilter() {
    if (_allNodes.isEmpty) {
      _filteredNodes = [];
      _filteredLinks = [];
      notifyListeners();
      return;
    }

    final Set<String> connectedNodeIds = {};
    for (final link in _allLinks) {
      connectedNodeIds.add(link.sourceId);
      connectedNodeIds.add(link.targetId);
    }

    switch (_filterMode) {
      case GraphFilterMode.all:
        _filteredNodes = List.from(_allNodes);
        _filteredLinks = List.from(_allLinks);
        break;
      case GraphFilterMode.connected:
        _filteredNodes =
            _allNodes.where((n) => connectedNodeIds.contains(n.id)).toList();
        _filteredLinks = List.from(_allLinks);
        break;
      case GraphFilterMode.isolated:
        _filteredNodes =
            _allNodes.where((n) => !connectedNodeIds.contains(n.id)).toList();
        _filteredLinks = [];
        break;
    }
    notifyListeners();
  }

  // ✨ [추가] 파일 감시 시작
  Future<void> startWatching() async {
    if (_isWatching || _isAiGraphView) return;

    try {
      final notesDir = await getNotesDirectory();
      _watcher = DirectoryWatcher(notesDir);

      _watcherSubscription = _watcher!.events.listen((event) {
        if (p.extension(event.path).toLowerCase() == '.md') {
          debugPrint(
            '📂 File event: ${event.type} - ${p.basename(event.path)}',
          );

          // 변경 사항을 모아서 처리 (디바운싱)
          _pendingChanges.add(event.path);

          _processingDebounce?.cancel();
          _processingDebounce = Timer(const Duration(milliseconds: 500), () {
            _processPendingChanges();
          });
        }
      });

      _isWatching = true;
      debugPrint('👀 Started watching: $notesDir');
    } catch (e) {
      debugPrint('❌ Failed to start watching: $e');
    }
  }

  // ✨ [추가] 누적된 변경사항 처리
  Future<void> _processPendingChanges() async {
    if (_pendingChanges.isEmpty) return;

    final changesToProcess = Set<String>.from(_pendingChanges);
    _pendingChanges.clear();

    debugPrint('🔄 Processing ${changesToProcess.length} file changes...');

    for (final filePath in changesToProcess) {
      await _handleFileChange(filePath);
    }
  }

  // ✨ [추가] 개별 파일 변경 처리
  Future<void> _handleFileChange(String filePath) async {
    try {
      final notesDir = await getNotesDirectory();
      final fileName = _normalizePath(p.relative(filePath, from: notesDir));
      final file = File(filePath);

      if (await file.exists()) {
        // 파일이 존재 -> 추가 또는 수정
        await _addOrUpdateNote(fileName, file);
      } else {
        // 파일이 없음 -> 삭제
        await _removeNote(fileName);
      }
    } catch (e) {
      debugPrint('❌ Error handling file change: $e');
    }
  }

  // ✨ [추가] 노트 추가/수정 (증분 업데이트)
  Future<void> _addOrUpdateNote(String fileName, File file) async {
    try {
      final content = await file.readAsString();
      final links = _parseWikiLinks(content);

      // 기존 링크 정보 백업
      final oldNodeInfo = _userGraphData[fileName];
      final oldOutgoingLinks = oldNodeInfo?.outgoingLinks ?? [];

      // 새 정보로 업데이트
      _userGraphData[fileName] = UserGraphNodeInfo(
        fileName: fileName,
        outgoingLinks: links,
      );

      // 영향받는 incoming 링크 재계산
      _recalculateIncomingLinks(fileName, oldOutgoingLinks, links);

      // 노드/링크 리스트 재구성
      _rebuildNodesAndLinks();

      debugPrint('✅ Updated: $fileName (${links.length} outgoing links)');
    } catch (e) {
      debugPrint('❌ Error adding/updating note: $e');
    }
  }

  // ✨ [추가] 노트 삭제 (증분 업데이트)
  Future<void> _removeNote(String fileName) async {
    final oldNodeInfo = _userGraphData.remove(fileName);

    if (oldNodeInfo != null) {
      // 이 노트가 가리키던 링크들의 incoming 링크 제거
      _recalculateIncomingLinks(fileName, oldNodeInfo.outgoingLinks, []);

      // 노드 위치 정보도 제거
      _nodePositions.remove(fileName);

      // 노드/링크 리스트 재구성
      _rebuildNodesAndLinks();

      debugPrint('🗑️ Removed: $fileName');
    }
  }

  // ✨ [추가] Incoming 링크 재계산
  void _recalculateIncomingLinks(
    String sourceFileName,
    List<String> oldLinks,
    List<String> newLinks,
  ) {
    final fileNameToPathLookup = _buildFileNameLookup();

    // 제거된 링크 처리
    for (final oldLink in oldLinks) {
      if (!newLinks.contains(oldLink)) {
        final targetPath = fileNameToPathLookup[oldLink.toLowerCase()];
        if (targetPath != null) {
          _userGraphData[targetPath]?.incomingLinks.remove(sourceFileName);
        }
      }
    }

    // 추가된 링크 처리
    for (final newLink in newLinks) {
      final targetPath = fileNameToPathLookup[newLink.toLowerCase()];
      if (targetPath != null) {
        _userGraphData[targetPath]?.incomingLinks.add(sourceFileName);
      }
    }
  }

  // ✨ [추가] 파일명 -> 경로 매핑 생성
  Map<String, String> _buildFileNameLookup() {
    final Map<String, String> lookup = {};
    for (final fullPath in _userGraphData.keys) {
      final baseName = p.basenameWithoutExtension(fullPath).toLowerCase();
      lookup[baseName] = fullPath;
    }
    return lookup;
  }

  // ✨ [추가] 노드와 링크 리스트 재구성
  void _rebuildNodesAndLinks() {
    _allNodes =
        _userGraphData.values
            .map(
              (info) =>
                  GraphNode(id: info.fileName, linkCount: info.totalLinks),
            )
            .toList();

    final fileNameToPathLookup = _buildFileNameLookup();
    _allLinks = [];

    for (final nodeInfo in _userGraphData.values) {
      for (final linkName in nodeInfo.outgoingLinks) {
        final targetPath = fileNameToPathLookup[linkName.toLowerCase()];
        if (targetPath != null) {
          _allLinks.add(
            GraphLink(sourceId: nodeInfo.fileName, targetId: targetPath),
          );
        }
      }
    }

    _statusMessage = '${_allNodes.length}개의 노드, ${_allLinks.length}개의 링크';
    _applyFilter();
  }

  // ✨ [수정] 파일 감시 중단
  void stopWatching() {
    _watcherSubscription?.cancel();
    _watcherSubscription = null;
    _processingDebounce?.cancel();
    _processingDebounce = null;
    _watcher = null;
    _isWatching = false;
    _pendingChanges.clear();
    debugPrint('🛑 Stopped watching');
  }

  String _normalizePath(String path) {
    return p.normalize(path).replaceAll(r'\', '/').trim();
  }

  List<String> _parseWikiLinks(String content) {
    final RegExp wikiLinkPattern = RegExp(r'\[\[([^\]]+)\]\]');
    final matches = wikiLinkPattern.allMatches(content);
    final links = <String>[];

    for (var match in matches) {
      String link = match.group(1)!;

      if (link.contains('|')) link = link.split('|')[0];
      if (link.contains('#')) link = link.split('#')[0];

      link = link.trim();

      if (link.endsWith('.md')) {
        link = link.substring(0, link.length - 3);
      }

      link =
          link
              .replaceAll(RegExp(r'[^\p{L}\p{N}\s\-_./]', unicode: true), '')
              .trim();

      if (link.isNotEmpty) {
        links.add(link);
      }
    }
    return links;
  }

  // ✨ [수정] 초기 빌드 (기존 방식 유지하되 감시 시작)
  Future<void> buildUserGraph() async {
    _isLoading = true;
    _isAiGraphView = false;
    _statusMessage = '사용자 링크 분석 중...';
    notifyListeners();

    try {
      await _loadNodePositions();
      final notesDir = await getNotesDirectory();
      final localFiles = await _getAllMarkdownFiles(Directory(notesDir));

      if (localFiles.isEmpty) {
        _statusMessage = '표시할 노트가 없습니다.';
        _allNodes = [];
        _allLinks = [];
      } else {
        _userGraphData.clear();

        for (var file in localFiles) {
          final fileName = _normalizePath(
            p.relative(file.path, from: notesDir),
          );
          final content = await file.readAsString();
          final links = _parseWikiLinks(content);
          _userGraphData[fileName] = UserGraphNodeInfo(
            fileName: fileName,
            outgoingLinks: links,
          );
        }

        final fileNameToPathLookup = _buildFileNameLookup();

        for (final nodeInfo in _userGraphData.values) {
          for (final linkName in nodeInfo.outgoingLinks) {
            final targetFullPath = fileNameToPathLookup[linkName.toLowerCase()];
            if (targetFullPath != null) {
              _userGraphData[targetFullPath]?.incomingLinks.add(
                nodeInfo.fileName,
              );
            }
          }
        }

        _allNodes =
            _userGraphData.values
                .map(
                  (info) =>
                      GraphNode(id: info.fileName, linkCount: info.totalLinks),
                )
                .toList();

        _allLinks = [];
        for (final nodeInfo in _userGraphData.values) {
          for (final linkName in nodeInfo.outgoingLinks) {
            final targetFullPath = fileNameToPathLookup[linkName.toLowerCase()];
            if (targetFullPath != null) {
              _allLinks.add(
                GraphLink(
                  sourceId: nodeInfo.fileName,
                  targetId: targetFullPath,
                ),
              );
            }
          }
        }
        await _loadAndMergeAiGraphData();
        _statusMessage = '${_allNodes.length}개의 노드, ${_allLinks.length}개의 링크';
      }
      _applyFilter();

      // ✨ [추가] 빌드 완료 후 감시 시작
      if (!_isAiGraphView) {
        startWatching();
      }
    } catch (e) {
      _statusMessage = '사용자 그래프 생성 중 오류 발생: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveNodePositions() async {
    try {
      final notesDir = await getNotesDirectory();
      final layoutFile = File(p.join(notesDir, 'user_graph_layout.json'));
      await layoutFile.writeAsString(jsonEncode(_nodePositions));
      debugPrint('Graph layout saved.');
    } catch (e) {
      debugPrint('Failed to save graph layout: $e');
    }
  }

  Future<void> _loadNodePositions() async {
    try {
      final notesDir = await getNotesDirectory();
      final layoutFile = File(p.join(notesDir, 'user_graph_layout.json'));
      if (await layoutFile.exists()) {
        final content = await layoutFile.readAsString();
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        _nodePositions = decoded.map(
          (key, value) => MapEntry(key, Map<String, double>.from(value)),
        );
        debugPrint('Graph layout loaded.');
      }
    } catch (e) {
      debugPrint('Failed to load graph layout: $e');
      _nodePositions = {};
    }
  }

  void updateAndSaveAllNodePositions(Map<String, Offset> finalPositions) {
    _nodePositions = finalPositions.map(
      (key, value) => MapEntry(key, {'dx': value.dx, 'dy': value.dy}),
    );
    if (_saveDebounce?.isActive ?? false) _saveDebounce!.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      _saveNodePositions();
    });
  }

  Future<void> generateAndMergeAiGraphData(BuildContext context) async {
    if (_isLoading) return;

    final statusBar = context.read<StatusBarProvider>();
    _isLoading = true;
    _statusMessage = 'AI 관계 분석을 위해 노트 파일을 스캔 중...';
    statusBar.showStatusMessage(_statusMessage, type: StatusType.info);
    notifyListeners();

    try {
      final notesDir = await getNotesDirectory();
      final localFiles = await _getAllMarkdownFiles(Directory(notesDir));

      if (localFiles.isEmpty) {
        _statusMessage = '분석할 노트 파일이 없습니다.';
        statusBar.showStatusMessage(_statusMessage, type: StatusType.info);
        return;
      }

      _statusMessage = '${localFiles.length}개 노트의 관계 분석을 AI 서버에 요청합니다...';
      statusBar.showStatusMessage(_statusMessage, type: StatusType.info);
      notifyListeners();

      List<Map<String, String>> notesData = [];
      for (var file in localFiles) {
        notesData.add({
          'fileName': _normalizePath(p.relative(file.path, from: notesDir)),
          'content': await file.readAsString(),
        });
      }

      final graphData = await ai_service.generateGraphData(notesData);

      if (graphData == null || graphData.containsKey('error')) {
        throw Exception('백엔드 API 오류: ${graphData?['error'] ?? '알 수 없는 오류'}');
      }

      final newLinks =
          (graphData['edges'] as List? ?? [])
              .map(
                (edge) => GraphLink(
                  sourceId: edge['from'],
                  targetId: edge['to'],
                  strength: (edge['similarity'] as num?)?.toDouble() ?? 0.0,
                ),
              )
              .toList();

      if (newLinks.isEmpty) {
        statusBar.showStatusMessage(
          'AI가 새로운 관계를 찾지 못했습니다.',
          type: StatusType.info,
        );
        return;
      }

      final existingLinksSet =
          _allLinks.map((e) => '${e.sourceId}|${e.targetId}').toSet();
      int addedCount = 0;

      for (final link in newLinks) {
        if (!existingLinksSet.contains('${link.sourceId}|${link.targetId}') &&
            !existingLinksSet.contains('${link.targetId}|${link.sourceId}')) {
          _allLinks.add(link);
          addedCount++;
        }
      }

      await _saveAiGraphData(_allLinks);

      _statusMessage =
          '${_allNodes.length}개의 노드, ${_allLinks.length}개의 링크 ($addedCount개 추가됨)';
      statusBar.showStatusMessage(
        'AI 관계 분석 완료! $addedCount개의 새로운 링크를 추가했습니다.',
        type: StatusType.success,
      );
      _applyFilter();
    } catch (e) {
      _statusMessage = 'AI 관계 분석 중 오류 발생';
      statusBar.showStatusMessage(
        '오류: ${e.toString().replaceAll("Exception: ", "")}',
        type: StatusType.error,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveAiGraphData(List<GraphLink> links) async {
    try {
      final notesDir = await getNotesDirectory();
      final aiGraphFile = File(p.join(notesDir, 'ai_graph_data.json'));
      final data =
          links
              .map(
                (e) => {
                  'from': e.sourceId,
                  'to': e.targetId,
                  'similarity': e.strength,
                },
              )
              .toList();
      await aiGraphFile.writeAsString(jsonEncode({'edges': data}));
    } catch (e) {
      debugPrint('AI 그래프 데이터 저장 실패: $e');
    }
  }

  Future<void> _loadAndMergeAiGraphData() async {
    try {
      final notesDir = await getNotesDirectory();
      final aiGraphFile = File(p.join(notesDir, 'ai_graph_data.json'));

      if (await aiGraphFile.exists()) {
        final content = await aiGraphFile.readAsString();
        final data = jsonDecode(content);
        final loadedLinks =
            (data['edges'] as List? ?? [])
                .map(
                  (edge) => GraphLink(
                    sourceId: edge['from'],
                    targetId: edge['to'],
                    strength: (edge['similarity'] as num?)?.toDouble() ?? 0.0,
                  ),
                )
                .toList();

        final existingLinksSet =
            _allLinks.map((e) => '${e.sourceId}|${e.targetId}').toSet();
        int addedCount = 0;
        for (final link in loadedLinks) {
          if (!existingLinksSet.contains('${link.sourceId}|${link.targetId}') &&
              !existingLinksSet.contains('${link.targetId}|${link.sourceId}')) {
            _allLinks.add(link);
            addedCount++;
          }
        }
        if (addedCount > 0) {
          debugPrint('$addedCount개의 저장된 AI 링크를 그래프에 추가했습니다.');
        }
      }
    } catch (e) {
      debugPrint('AI 그래프 데이터 로드 실패: $e');
    }
  }

  Future<String> getNotesDirectory() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('홈 디렉터리를 찾을 수 없습니다.');
    return Platform.isMacOS
        ? p.join(home, 'Memordo_Notes')
        : p.join(home, 'Documents', 'Memordo_Notes');
  }

  Future<List<File>> _getAllMarkdownFiles(Directory dir) async {
    final List<File> mdFiles = [];
    if (!await dir.exists()) return mdFiles;
    await for (var entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.md') {
        mdFiles.add(entity);
      }
    }
    return mdFiles;
  }

  @override
  void dispose() {
    stopWatching();
    _saveDebounce?.cancel();
    super.dispose();
  }
}
