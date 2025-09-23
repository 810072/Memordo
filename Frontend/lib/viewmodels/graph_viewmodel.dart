// lib/viewmodels/graph_viewmodel.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:path/path.dart' as p;
import '../utils/ai_service.dart' as ai_service;
import '../features/graph_page.dart'; // 데이터 모델 클래스를 위해 임포트

class GraphViewModel with ChangeNotifier {
  final Graph graph = Graph();
  late Algorithm builder;

  bool _isLoading = false;
  bool _showUserGraph = false;
  String _statusMessage = '그래프를 생성하려면 우측 상단의 버튼을 눌러주세요.';

  static const double _similarityThreshold = 0.8;
  final double _canvasWidth = 4000;
  final double _canvasHeight = 4000;

  List<GraphEdgeData> _aiEdges = [];
  List<GraphEdgeData> _userEdges = [];
  final Map<String, Node> _nodeMap = {};
  final Set<String> _activeUserNodeIds = {};

  // Getter for UI
  bool get isLoading => _isLoading;
  bool get showUserGraph => _showUserGraph;
  String get statusMessage => _statusMessage;
  double get canvasWidth => _canvasWidth;
  double get canvasHeight => _canvasHeight;

  // ✨ [수정] 생성자에서 데이터 로딩 호출 제거
  GraphViewModel();

  void toggleGraphView() {
    if (_isLoading || _nodeMap.isEmpty) return;
    _showUserGraph = !_showUserGraph;
    _updateEdges();
    notifyListeners();
  }

  Future<void> triggerEmbeddingProcess(BuildContext context) async {
    if (_isLoading) return;
    _isLoading = true;
    _statusMessage = '로컬 노트 파일 스캔 중...';
    notifyListeners();

    try {
      final notesDir = await getNotesDirectory();
      final localFiles = await _getAllMarkdownFiles(Directory(notesDir));

      if (localFiles.isEmpty) {
        _showSnackBar(context, '노트 폴더에 분석할 .md 파일이 없습니다.');
        _isLoading = false;
        notifyListeners();
        return;
      }

      _statusMessage = '${localFiles.length}개 노트의 관계 분석을 AI 서버에 요청합니다...';
      notifyListeners();

      List<Map<String, String>> notesData = [];
      for (var file in localFiles) {
        notesData.add({
          'fileName': p.relative(file.path, from: notesDir),
          'content': await file.readAsString(),
        });
      }

      // 백엔드에 그래프 데이터 생성을 요청
      final graphData = await ai_service.generateGraphData(notesData);

      if (graphData == null || graphData.containsKey('error')) {
        final errorMessage = graphData?['error'] ?? '알 수 없는 오류';
        throw Exception('백엔드 API 오류: $errorMessage');
      }

      // 사용자 정의 엣지 및 토픽 추출
      final userDefinedResult = await _extractUserDefinedEdgesAndTopics(
        notesData,
      );

      // 최종 데이터 합치기
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

      // `embeddings.json` 파일에 최종 결과 저장 (캐시/초기 로딩용)
      final embeddingsFile = File(p.join(notesDir, 'embeddings.json'));
      await embeddingsFile.writeAsString(jsonEncode(finalData));

      _showSnackBar(context, '그래프 생성 완료!');
      _buildGraphFromData(finalData);
    } catch (e) {
      _showSnackBar(context, '오류 발생: ${e.toString()}');
      _statusMessage = '오류가 발생했습니다.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _setAlgorithm() {
    builder = FruchtermanReingoldAlgorithm(iterations: 8000);
  }

  void _updateEdges() {
    graph.edges.clear();
    final edgesToShow = _showUserGraph ? _userEdges : _aiEdges;

    for (var edgeData in edgesToShow) {
      if (!_showUserGraph && edgeData.similarity < _similarityThreshold) {
        continue;
      }
      final fromNode = _nodeMap[edgeData.from];
      final toNode = _nodeMap[edgeData.to];

      if (fromNode != null && toNode != null) {
        final paint =
            Paint()
              ..color =
                  _showUserGraph
                      ? Colors.blue
                      : Colors.grey.withOpacity(edgeData.similarity)
              ..strokeWidth =
                  _showUserGraph
                      ? 2.5
                      : (1.0 + (edgeData.similarity - 0.75) * 16).clamp(
                        1.0,
                        5.0,
                      );
        graph.addEdge(fromNode, toNode, paint: paint);
      }
    }
  }

  void _buildGraphFromData(Map<String, dynamic> data) {
    graph.nodes.clear();
    graph.edges.clear();
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
    }

    _setAlgorithm();
    for (var node in _nodeMap.values) {
      graph.addNode(node);
    }
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

  void _showSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
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

  // ✨ [수정] UI 관련 메서드 제거

  bool isUserNodeActive(String label) {
    return _activeUserNodeIds.contains(label);
  }
}
