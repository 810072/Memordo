// lib/viewmodels/graph_viewmodel.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../utils/ai_service.dart' as ai_service;
import '../features/graph_page.dart';
import '../providers/status_bar_provider.dart';

class GraphViewModel with ChangeNotifier {
  // AI 그래프용
  final Graph aiGraph = Graph();
  late Algorithm aiGraphBuilder;

  // 사용자 정의 그래프용
  final Graph userGraph = Graph();
  late Algorithm userGraphBuilder;
  bool _isUserGraphBuilt = false;
  String _userGraphStatusMessage = '사용자 그래프를 불러오세요.';

  bool _isLoading = false;
  String _statusMessage = '그래프를 생성하려면 우측 상단의 버튼을 눌러주세요.';
  bool _isAiGraphView = true;

  static const double _similarityThreshold = 0.8;
  final double _canvasWidth = 4000;
  final double _canvasHeight = 4000;

  List<GraphEdgeData> _aiEdges = [];
  List<GraphEdgeData> _userEdges = [];
  final Map<String, Node> _nodeMap = {};
  final Set<String> _activeUserNodeIds = {};

  bool get isLoading => _isLoading;
  String get statusMessage =>
      _isAiGraphView ? _statusMessage : _userGraphStatusMessage;
  double get canvasWidth => _canvasWidth;
  double get canvasHeight => _canvasHeight;
  bool get isAiGraphView => _isAiGraphView;

  GraphViewModel();

  void setGraphView(bool isAiView) {
    if (_isAiGraphView != isAiView) {
      _isAiGraphView = isAiView;
      notifyListeners();
    }
  }

  // 사용자 정의 그래프를 만드는 메서드
  Future<void> buildUserGraph() async {
    if (_isUserGraphBuilt) {
      setGraphView(false);
      return;
    }

    _isLoading = true;
    _isAiGraphView = false; // 사용자 그래프 뷰로 전환
    notifyListeners();

    try {
      final notesDir = await getNotesDirectory();
      final localFiles = await _getAllMarkdownFiles(Directory(notesDir));

      if (localFiles.isEmpty) {
        _userGraphStatusMessage = '표시할 노트가 없습니다.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      userGraph.nodes.clear();

      for (var file in localFiles) {
        final fileName = p.relative(file.path, from: notesDir);
        final node = Node.Id(fileName);
        userGraph.addNode(node);
      }

      // ✨ [핵심 수정] FruchtermanReingold 알고리즘을 다시 사용하여 노드들이 서로 밀어내도록 합니다.
      userGraphBuilder = FruchtermanReingoldAlgorithm(iterations: 600);

      // ✨ [추가] 알고리즘이 안정적으로 노드를 배치할 수 있도록, 초기 위치를 넓은 그리드에 설정합니다.
      final double nodeWidthSpacing = 300; // 노드 간 가로 간격을 넓게 설정
      final double nodeHeightSpacing = 150; // 노드 간 세로 간격 설정
      final int count = userGraph.nodeCount();
      final int columns = (sqrt(count) * 1.2).ceil(); // 가로로 더 넓게 퍼지도록 조정

      for (var i = 0; i < count; i++) {
        final node = userGraph.nodes[i];
        final dx = (i % columns) * nodeWidthSpacing;
        final dy = (i ~/ columns) * nodeHeightSpacing;
        node.position = Offset(dx.toDouble(), dy.toDouble());
      }

      _isUserGraphBuilt = true;
      _userGraphStatusMessage = '${localFiles.length}개의 노드를 찾았습니다.';
    } catch (e) {
      _userGraphStatusMessage = '사용자 그래프 생성 중 오류 발생: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> triggerEmbeddingProcess(BuildContext context) async {
    if (_isLoading) return;

    if (!_isAiGraphView) {
      setGraphView(true);
      await Future.delayed(const Duration(milliseconds: 100));
    }

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
        statusBar.showStatusMessage(_statusMessage, type: StatusType.error);
        _isLoading = false;
        notifyListeners();
        return;
      }

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
        final errorMessage = graphData?['error'] ?? '알 수 없는 오류';
        throw Exception('백엔드 API 오류: $errorMessage');
      }

      final userDefinedResult = await _extractUserDefinedEdgesAndTopics(
        notesData,
      );

      final finalData = {
        "nodes": graphData['nodes'],
        "edges": graphData['edges'],
        "userEdges":
            userDefinedResult.userEdges
                .map(
                  (e) => {
                    "from": e.from,
                    "to": e.to,
                    "similarity": e.similarity,
                  },
                )
                .toList(),
        "userTopics": userDefinedResult.topicNodes.toList(),
      };

      final embeddingsFile = File(p.join(notesDir, 'embeddings.json'));
      await embeddingsFile.writeAsString(jsonEncode(finalData));

      statusBar.showStatusMessage('그래프 생성 완료!', type: StatusType.success);
      _buildGraphFromData(finalData);
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

  void _setAiAlgorithm() {
    aiGraphBuilder = FruchtermanReingoldAlgorithm(iterations: 8000);
  }

  void _updateEdges() {
    aiGraph.edges.clear();
    final edgesToShow = _aiEdges;

    for (var edgeData in edgesToShow) {
      if (edgeData.similarity < _similarityThreshold) continue;

      final fromNode = _nodeMap[edgeData.from];
      final toNode = _nodeMap[edgeData.to];

      if (fromNode != null && toNode != null) {
        final paint =
            Paint()
              ..color = Colors.grey.withOpacity(edgeData.similarity)
              ..strokeWidth = (1.0 + (edgeData.similarity - 0.75) * 16).clamp(
                1.0,
                5.0,
              );
        aiGraph.addEdge(fromNode, toNode, paint: paint);
      }
    }
  }

  void _buildGraphFromData(Map<String, dynamic> data) {
    aiGraph.nodes.clear();
    aiGraph.edges.clear();
    _nodeMap.clear();

    final topicIds =
        (data['userTopics'] as List? ?? []).whereType<String>().toSet();
    final allNodesData =
        (data['nodes'] as List? ?? [])
            .map((nodeJson) => GraphNodeData.fromJson(nodeJson))
            .toList();
    _aiEdges =
        (data['edges'] as List? ?? [])
            .map((edgeJson) => GraphEdgeData.fromJson(edgeJson))
            .toList();
    _userEdges =
        (data['userEdges'] as List? ?? [])
            .map((edgeJson) => GraphEdgeData.fromJson(edgeJson))
            .toList();

    _activeUserNodeIds.clear();
    for (var edge in _userEdges) {
      _activeUserNodeIds.add(edge.from);
      _activeUserNodeIds.add(edge.to);
    }

    for (var nodeData in allNodesData) {
      _nodeMap[nodeData.id] = Node.Id(nodeData.id);
    }
    for (var topic in topicIds) {
      if (!_nodeMap.containsKey(topic)) {
        _nodeMap[topic] = Node.Id(topic);
      }
    }

    if (_nodeMap.isEmpty) {
      _statusMessage = '표시할 노트가 없습니다.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    final random = Random();
    for (var node in _nodeMap.values) {
      node.position = Offset(
        random.nextDouble() * _canvasWidth,
        random.nextDouble() * _canvasHeight,
      );
      aiGraph.addNode(node);
    }

    _setAiAlgorithm();
    _updateEdges();

    _isLoading = false;
    notifyListeners();
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
        _buildGraphFromData(data);
      } else {
        _statusMessage = '임베딩 파일이 없습니다. 우측 상단 버튼을 눌러 생성해주세요.';
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      _statusMessage = '그래프 파일 로딩 중 오류 발생: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> getNotesDirectory() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('홈 디렉토리를 찾을 수 없습니다.');
    return Platform.isMacOS
        ? p.join(home, 'Memordo_Notes')
        : p.join(home, 'Documents', 'Memordo_Notes');
  }

  Future<List<File>> _getAllMarkdownFiles(Directory dir) async {
    final List<File> mdFiles = [];
    await for (var entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.md') {
        mdFiles.add(entity);
      }
    }
    return mdFiles;
  }

  Future<({List<GraphEdgeData> userEdges, Set<String> topicNodes})>
  _extractUserDefinedEdgesAndTopics(List<Map<String, String>> notesData) async {
    final userEdges = <GraphEdgeData>[];
    final topicNodes = <String>{};
    final allNoteFileNames = notesData.map((e) => e['fileName']!).toSet();
    for (final note in notesData) {
      final fileName = note['fileName']!;
      final content = note['content']!;
      final matches = RegExp(r'<<([^<>]+)>>').allMatches(content);
      for (final match in matches) {
        final target = match.group(1)?.trim();
        if (target != null && target.isNotEmpty) {
          final targetMd = target.endsWith('.md') ? target : '$target.md';
          if (targetMd != fileName && allNoteFileNames.contains(targetMd)) {
            userEdges.add(
              GraphEdgeData(from: fileName, to: targetMd, similarity: 1.0),
            );
          } else if (targetMd != fileName) {
            userEdges.add(
              GraphEdgeData(from: fileName, to: target, similarity: 1.0),
            );
            topicNodes.add(target);
          }
        }
      }
    }
    return (userEdges: userEdges, topicNodes: topicNodes);
  }

  bool isUserNodeActive(String label) {
    return _activeUserNodeIds.contains(label);
  }
}
