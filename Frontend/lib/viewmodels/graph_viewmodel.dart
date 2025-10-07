// lib/viewmodels/graph_viewmodel.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../utils/ai_service.dart' as ai_service;
import '../widgets/force_graph_widget.dart';
import '../providers/status_bar_provider.dart';

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
  bool _isAiGraphView = true;

  List<GraphNode> _nodes = [];
  List<GraphLink> _links = [];

  // ✨ [오류 수정] 누락되었던 _userGraphData 변수 선언을 다시 추가합니다.
  final Map<String, UserGraphNodeInfo> _userGraphData = {};

  // ✨ [추가] 노드 위치를 저장하고 관리하기 위한 변수들
  Map<String, Map<String, double>> _nodePositions = {};
  Timer? _saveDebounce;

  bool get isLoading => _isLoading;
  String get statusMessage => _statusMessage;
  bool get isAiGraphView => _isAiGraphView;
  List<GraphNode> get nodes => _nodes;
  List<GraphLink> get links => _links;
  // ✨ [추가] 뷰에서 노드 위치를 가져갈 수 있도록 getter 추가
  Map<String, Map<String, double>> get nodePositions => _nodePositions;

  int getNodeLinkCount(String nodeId) {
    if (_isAiGraphView) {
      return _links
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

  void setGraphView(bool isAiView) {
    if (_isAiGraphView != isAiView) {
      _isAiGraphView = isAiView;
      if (isAiView) {
        loadGraphFromEmbeddingsFile();
      } else {
        buildUserGraph();
      }
      notifyListeners();
    }
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

  Future<void> buildUserGraph() async {
    _isLoading = true;
    _isAiGraphView = false;
    _statusMessage = '사용자 링크 분석 중...';
    notifyListeners();

    try {
      // ✨ [추가] 그래프를 빌드하기 전에 저장된 노드 위치를 불러옵니다.
      await _loadNodePositions();
      final notesDir = await getNotesDirectory();
      final localFiles = await _getAllMarkdownFiles(Directory(notesDir));

      if (localFiles.isEmpty) {
        _statusMessage = '표시할 노트가 없습니다.';
        _nodes = [];
        _links = [];
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

        final Map<String, String> fileNameToPathLookup = {};
        for (final fullPath in _userGraphData.keys) {
          final baseName = p.basenameWithoutExtension(fullPath).toLowerCase();
          if (!fileNameToPathLookup.containsKey(baseName)) {
            fileNameToPathLookup[baseName] = fullPath;
          } else {
            debugPrint(
              'Warning: Duplicate filename found: ${p.basename(fullPath)}. Link resolution may be ambiguous.',
            );
          }
        }

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

        _nodes =
            _userGraphData.values
                .map(
                  (info) =>
                      GraphNode(id: info.fileName, linkCount: info.totalLinks),
                )
                .toList();

        _links = [];
        for (final nodeInfo in _userGraphData.values) {
          for (final linkName in nodeInfo.outgoingLinks) {
            final targetFullPath = fileNameToPathLookup[linkName.toLowerCase()];
            if (targetFullPath != null) {
              _links.add(
                GraphLink(
                  sourceId: nodeInfo.fileName,
                  targetId: targetFullPath,
                ),
              );
            }
          }
        }

        _statusMessage = '${_nodes.length}개의 노드, ${_links.length}개의 링크';
      }
    } catch (e) {
      _statusMessage = '사용자 그래프 생성 중 오류 발생: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ✨ [추가] 노드 위치를 파일에 저장하는 기능
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

  // ✨ [추가] 파일에서 노드 위치를 불러오는 기능
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

  // ✨ [추가] 그래프 레이아웃이 안정화되면 호출되어 위치를 저장하는 기능
  void updateAndSaveAllNodePositions(Map<String, Offset> finalPositions) {
    _nodePositions = finalPositions.map(
      (key, value) => MapEntry(key, {'dx': value.dx, 'dy': value.dy}),
    );
    // 디바운스를 사용하여 파일 쓰기 작업을 최적화합니다.
    if (_saveDebounce?.isActive ?? false) _saveDebounce!.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      _saveNodePositions();
    });
  }

  Future<void> triggerEmbeddingProcess(BuildContext context) async {
    if (_isLoading) return;
    if (!_isAiGraphView) setGraphView(true);

    final statusBar = context.read<StatusBarProvider>();
    _isLoading = true;
    _statusMessage = '로컬 노트 파일 스캔 중...';
    statusBar.showStatusMessage(_statusMessage, type: StatusType.info);
    notifyListeners();

    try {
      final notesDir = await getNotesDirectory();
      final localFiles = await _getAllMarkdownFiles(Directory(notesDir));

      if (localFiles.isEmpty) {
        _statusMessage = '노트 폴더에 분석할 .md 파일이 없습니다.';
        _nodes = [];
        _links = [];
        statusBar.showStatusMessage(_statusMessage, type: StatusType.error);
      } else {
        _statusMessage = '${localFiles.length}개 노트의 관계 분석을 AI 서버에 요청합니다...';
        statusBar.showStatusMessage(_statusMessage, type: StatusType.info);
        notifyListeners();

        List<Map<String, String>> notesData = [];
        for (var file in localFiles) {
          notesData.add({
            'fileName': p.relative(file.path, from: notesDir),
            'content': await file.readAsString(),
          });
        }
        final graphData = await ai_service.generateGraphData(notesData);

        if (graphData == null || graphData.containsKey('error')) {
          throw Exception('백엔드 API 오류: ${graphData?['error'] ?? '알 수 없는 오류'}');
        }

        final embeddingsFile = File(p.join(notesDir, 'embeddings.json'));
        await embeddingsFile.writeAsString(jsonEncode(graphData));

        statusBar.showStatusMessage('그래프 생성 완료!', type: StatusType.success);
        _buildAiGraphFromData(graphData);
      }
    } catch (e) {
      _statusMessage = '오류가 발생했습니다.';
      statusBar.showStatusMessage(
        '그래프 생성 중 오류 발생: ${e.toString()}',
        type: StatusType.error,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _buildAiGraphFromData(Map<String, dynamic> data) {
    const similarityThreshold = 0.8;

    _nodes =
        (data['nodes'] as List? ?? [])
            .map((nodeJson) => GraphNode(id: nodeJson['id']))
            .toList();

    _links =
        (data['edges'] as List? ?? [])
            .where(
              (edge) =>
                  (edge['similarity'] as num).toDouble() >= similarityThreshold,
            )
            .map(
              (edgeJson) => GraphLink(
                sourceId: edgeJson['from'],
                targetId: edgeJson['to'],
                strength: (edgeJson['similarity'] as num).toDouble(),
              ),
            )
            .toList();

    _statusMessage =
        _nodes.isEmpty ? '표시할 노트가 없습니다.' : '${_nodes.length}개의 노트와 관계';
  }

  Future<void> loadGraphFromEmbeddingsFile() async {
    _isLoading = true;
    _statusMessage = '저장된 임베딩 파일을 찾는 중...';
    notifyListeners();
    try {
      final notesDir = await getNotesDirectory();
      final embeddingsFile = File(p.join(notesDir, 'embeddings.json'));
      if (await embeddingsFile.exists()) {
        final data = jsonDecode(await embeddingsFile.readAsString());
        _buildAiGraphFromData(data);
      } else {
        _statusMessage = '임베딩 파일이 없습니다. 우측 상단 버튼을 눌러 생성해주세요.';
        _nodes = [];
        _links = [];
      }
    } catch (e) {
      _statusMessage = '그래프 파일 로딩 중 오류 발생: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
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
}
