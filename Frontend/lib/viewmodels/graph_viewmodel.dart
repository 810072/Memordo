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
  // --- ✨ [수정] 현재 뷰 상태 (false: User, true: AI) ---
  bool _isAiGraphView = false;

  List<GraphNode> _allNodes = [];
  // --- ✨ [수정] 링크 목록 분리 ---
  List<GraphLink> _userLinks = []; // 사용자 정의 링크 저장
  List<GraphLink> _aiLinks = []; // AI 추천 링크 저장
  List<GraphLink> _allLinks = []; // 현재 활성화된 링크 목록 ( _userLinks 또는 _aiLinks )
  // ---
  List<GraphNode> _filteredNodes = [];
  List<GraphLink> _filteredLinks = [];

  GraphFilterMode _filterMode = GraphFilterMode.all;
  GraphFilterMode get filterMode => _filterMode;

  final Map<String, UserGraphNodeInfo> _userGraphData = {};
  Map<String, Map<String, double>> _nodePositions = {};
  Timer? _saveDebounce;

  DirectoryWatcher? _watcher;
  StreamSubscription? _watcherSubscription;
  bool _isWatching = false;
  Timer? _processingDebounce;
  final Set<String> _pendingChanges = {};

  bool get isLoading => _isLoading;
  String get statusMessage => _statusMessage;
  bool get isAiGraphView => _isAiGraphView;
  List<GraphNode> get nodes => _filteredNodes;
  // --- ✨ [수정] getter는 _allLinks 기반 필터링 결과를 반환 ---
  List<GraphLink> get links => _filteredLinks;
  // ---
  Map<String, Map<String, double>> get nodePositions => _nodePositions;

  // --- getNodeLinkCount 함수 수정 ---
  int getNodeLinkCount(String nodeId) {
    // 현재 활성화된 링크(_allLinks) 기준으로 계산
    final currentLinks = _allLinks;
    return currentLinks
        .where((l) => l.sourceId == nodeId || l.targetId == nodeId)
        .length;
    /* // 이전 로직 주석 처리
    if (_isAiGraphView) {
      // AI 뷰일 때는 _aiLinks 또는 _allLinks 기준 (현재는 _allLinks 사용)
      return _allLinks
          .where((l) => l.sourceId == nodeId || l.targetId == nodeId)
          .length;
    } else {
      // 사용자 뷰일 때는 _userGraphData 기준
      final key = _userGraphData.keys.firstWhere(
        (k) => k.toLowerCase() == nodeId.toLowerCase(),
        orElse: () => '',
      );
      return _userGraphData[key]?.totalLinks ?? 0;
    }
    */
  }
  // ---

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
    // --- ✨ [수정] 현재 활성화된 _allLinks 사용 ---
    for (final link in _allLinks) {
      connectedNodeIds.add(link.sourceId);
      connectedNodeIds.add(link.targetId);
    }
    // ---

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

  Future<void> startWatching() async {
    if (_isWatching || _isAiGraphView) return; // AI 뷰에서는 감시 안 함

    try {
      final notesDir = await getNotesDirectory();
      _watcher = DirectoryWatcher(notesDir);

      _watcherSubscription = _watcher!.events.listen((event) {
        if (p.extension(event.path).toLowerCase() == '.md') {
          debugPrint(
            '📂 File event: ${event.type} - ${p.basename(event.path)}',
          );
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

  Future<void> _processPendingChanges() async {
    if (_pendingChanges.isEmpty || _isAiGraphView) return; // AI 뷰에서는 처리 안 함

    final changesToProcess = Set<String>.from(_pendingChanges);
    _pendingChanges.clear();
    debugPrint('🔄 Processing ${changesToProcess.length} file changes...');
    for (final filePath in changesToProcess) {
      await _handleFileChange(filePath);
    }
    // 변경 처리 후 UI 업데이트 보장
    _applyFilter();
    notifyListeners();
  }

  Future<void> _handleFileChange(String filePath) async {
    // AI 뷰에서는 파일 변경 무시
    if (_isAiGraphView) return;
    try {
      final notesDir = await getNotesDirectory();
      final fileName = _normalizePath(p.relative(filePath, from: notesDir));
      final file = File(filePath);

      if (await file.exists()) {
        await _addOrUpdateNote(fileName, file);
      } else {
        await _removeNote(fileName);
      }
    } catch (e) {
      debugPrint('❌ Error handling file change: $e');
    }
  }

  Future<void> _addOrUpdateNote(String fileName, File file) async {
    try {
      final content = await file.readAsString();
      final links = _parseWikiLinks(content);
      final oldNodeInfo = _userGraphData[fileName];
      final oldOutgoingLinks = oldNodeInfo?.outgoingLinks ?? [];

      _userGraphData[fileName] = UserGraphNodeInfo(
        fileName: fileName,
        outgoingLinks: links,
      );
      _recalculateIncomingLinks(fileName, oldOutgoingLinks, links);
      // 노드/링크 리스트 재구성 (사용자 링크만)
      _rebuildUserNodesAndLinks();
      debugPrint('✅ Updated: $fileName (${links.length} outgoing links)');
    } catch (e) {
      debugPrint('❌ Error adding/updating note: $e');
    }
  }

  Future<void> _removeNote(String fileName) async {
    final oldNodeInfo = _userGraphData.remove(fileName);
    if (oldNodeInfo != null) {
      _recalculateIncomingLinks(fileName, oldNodeInfo.outgoingLinks, []);
      _nodePositions.remove(fileName);
      // 노드/링크 리스트 재구성 (사용자 링크만)
      _rebuildUserNodesAndLinks();
      debugPrint('🗑️ Removed: $fileName');
    }
  }

  void _recalculateIncomingLinks(
    String sourceFileName,
    List<String> oldLinks,
    List<String> newLinks,
  ) {
    final fileNameToPathLookup = _buildFileNameLookup();
    for (final oldLink in oldLinks) {
      if (!newLinks.contains(oldLink)) {
        final targetPath = fileNameToPathLookup[oldLink.toLowerCase()];
        if (targetPath != null) {
          _userGraphData[targetPath]?.incomingLinks.remove(sourceFileName);
        }
      }
    }
    for (final newLink in newLinks) {
      final targetPath = fileNameToPathLookup[newLink.toLowerCase()];
      if (targetPath != null) {
        _userGraphData[targetPath]?.incomingLinks.add(sourceFileName);
      }
    }
  }

  Map<String, String> _buildFileNameLookup() {
    final Map<String, String> lookup = {};
    for (final fullPath in _userGraphData.keys) {
      final baseName = p.basenameWithoutExtension(fullPath).toLowerCase();
      lookup[baseName] = fullPath;
    }
    return lookup;
  }

  // --- ✨ [수정] 사용자 노드/링크만 재구성하는 함수 ---
  void _rebuildUserNodesAndLinks() {
    _allNodes =
        _userGraphData.values
            .map(
              (info) =>
                  GraphNode(id: info.fileName, linkCount: info.totalLinks),
            )
            .toList();

    final fileNameToPathLookup = _buildFileNameLookup();
    _userLinks = []; // 사용자 링크만 초기화 및 재구성
    for (final nodeInfo in _userGraphData.values) {
      for (final linkName in nodeInfo.outgoingLinks) {
        final targetPath = fileNameToPathLookup[linkName.toLowerCase()];
        if (targetPath != null) {
          _userLinks.add(
            GraphLink(sourceId: nodeInfo.fileName, targetId: targetPath),
          );
        }
      }
    }
    // AI 뷰가 아니면 활성 링크(_allLinks)도 업데이트
    if (!_isAiGraphView) {
      _allLinks = _userLinks;
    }
    _statusMessage = '${_allNodes.length}개의 노드, ${_userLinks.length}개의 링크';
    // applyFilter는 toggleGraphView 또는 buildUserGraph에서 호출되므로 여기서 직접 호출하지 않음
  }
  // ---

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

  // --- ✨ [수정] 사용자 그래프 빌드 함수 ---
  Future<void> buildUserGraph() async {
    _isLoading = true;
    _isAiGraphView = false; // 사용자 뷰로 명시적 설정
    _statusMessage = '사용자 링크 분석 중...';
    notifyListeners();

    try {
      await _loadNodePositions();
      final notesDir = await getNotesDirectory();
      final localFiles = await _getAllMarkdownFiles(Directory(notesDir));

      if (localFiles.isEmpty) {
        _statusMessage = '표시할 노트가 없습니다.';
        _allNodes = [];
        _userLinks = []; // 사용자 링크 초기화
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
        // _rebuildUserNodesAndLinks 호출하여 _allNodes와 _userLinks 업데이트
        _rebuildUserNodesAndLinks();
        // AI 데이터 로드 함수 호출 제거 (필요 시 loadAiGraph 호출)
        // await _loadAndMergeAiGraphData();
      }
      // _allLinks를 _userLinks로 설정
      _allLinks = _userLinks;
      _applyFilter();
      startWatching(); // 사용자 뷰이므로 감시 시작
    } catch (e) {
      _statusMessage = '사용자 그래프 생성 중 오류 발생: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  // ---

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

  // --- ✨ [수정] AI 그래프 로드 함수 (이름 변경 및 로직 수정) ---
  Future<void> loadAiGraph(BuildContext context) async {
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
        _aiLinks = []; // AI 링크 초기화
        statusBar.showStatusMessage(_statusMessage, type: StatusType.info);
        // AI 뷰로 전환은 toggleGraphView에서 처리하므로 여기서는 상태만 업데이트
        _isAiGraphView = true;
        _allLinks = _aiLinks;
        _applyFilter();
        return; // 파일 없으면 여기서 종료
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

      // 결과를 _aiLinks에 저장 (병합 안 함)
      _aiLinks =
          (graphData['edges'] as List? ?? [])
              .map(
                (edge) => GraphLink(
                  sourceId: edge['from'],
                  targetId: edge['to'],
                  strength: (edge['similarity'] as num?)?.toDouble() ?? 0.0,
                ),
              )
              .toList();

      // AI 노드 정보(_allNodes는 이미 사용자 노트 기준으로 생성되어 있음) 업데이트 불필요
      // _allNodes = (graphData['nodes'] as List? ?? [])
      //     .map((node) => GraphNode(id: node['id'], linkCount: node['linkCount'] ?? 0))
      //     .toList();

      // AI 그래프 데이터 저장 (선택적)
      // await _saveAiGraphData(_aiLinks); // 저장 필요 시 활성화

      // 활성 링크를 AI 링크로 설정하고 상태 업데이트
      _allLinks = _aiLinks;
      _isAiGraphView = true; // AI 뷰 상태로 설정
      _statusMessage =
          '${_allNodes.length}개의 노드, ${_aiLinks.length}개의 AI 추천 링크';
      statusBar.showStatusMessage(
        'AI 관계 분석 완료! ${_aiLinks.length}개의 관계를 표시합니다.',
        type: StatusType.success,
      );
      _applyFilter();
      stopWatching(); // AI 뷰에서는 감시 중단
    } catch (e) {
      _statusMessage = 'AI 관계 분석 중 오류 발생';
      statusBar.showStatusMessage(
        '오류: ${e.toString().replaceAll("Exception: ", "")}',
        type: StatusType.error,
      );
      // 오류 발생 시 AI 뷰 상태를 false로 되돌리고 사용자 링크를 활성화
      _isAiGraphView = false;
      _allLinks = _userLinks;
      _applyFilter();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  // ---

  // AI 그래프 데이터 저장 함수 (필요 시 사용)
  // Future<void> _saveAiGraphData(List<GraphLink> links) async { ... }

  // 저장된 AI 그래프 데이터 로드 함수 (앱 시작 시 또는 필요 시 사용)
  // Future<void> _loadAiGraphData() async { ... }

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

  // --- ✨ [추가] 뷰 전환 함수 ---
  void toggleGraphView(BuildContext context) {
    if (_isLoading) return; // 로딩 중에는 전환 방지

    _isAiGraphView = !_isAiGraphView; // 상태 전환

    if (_isAiGraphView) {
      // AI 뷰로 전환
      if (_aiLinks.isEmpty) {
        // AI 데이터가 없으면 로드
        loadAiGraph(context); // AI 데이터 로드 함수 호출
      } else {
        // AI 데이터가 있으면 즉시 적용
        _allLinks = _aiLinks;
        _statusMessage =
            '${_allNodes.length}개의 노드, ${_aiLinks.length}개의 AI 추천 링크';
        stopWatching(); // AI 뷰에서는 감시 중단
        _applyFilter(); // 필터 재적용 및 UI 갱신
        notifyListeners(); // 상태 변경 알림
      }
    } else {
      // 사용자 뷰로 전환
      // 사용자 데이터는 일반적으로 앱 시작 시 로드되므로, 없으면 로드하는 로직은 buildUserGraph에 있음
      _allLinks = _userLinks; // 활성 링크를 사용자 링크로 설정
      _statusMessage = '${_allNodes.length}개의 노드, ${_userLinks.length}개의 링크';
      startWatching(); // 사용자 뷰에서 감시 재시작
      _applyFilter(); // 필터 재적용 및 UI 갱신
      notifyListeners(); // 상태 변경 알림
    }
  }
  // ---

  @override
  void dispose() {
    stopWatching();
    _saveDebounce?.cancel();
    super.dispose();
  }
}
