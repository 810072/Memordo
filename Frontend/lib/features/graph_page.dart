// Frontend/lib/features/graph_page.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:path/path.dart' as p;
import './meeting_screen.dart';

import '../utils/ai_service.dart' as ai_service;
// import '../layout/main_layout.dart'; // MainLayout 임포트 제거
import 'page_type.dart';

// 서버로부터 받은 노드와 엣지 데이터를 담을 데이터 모델 클래스
class GraphNodeData {
  final String id;
  GraphNodeData({required this.id});
  factory GraphNodeData.fromJson(Map<String, dynamic> json) =>
      GraphNodeData(id: json['id']);
}

class GraphEdgeData {
  final String from;
  final String to;
  final double similarity;
  GraphEdgeData({
    required this.from,
    required this.to,
    required this.similarity,
  });
  factory GraphEdgeData.fromJson(Map<String, dynamic> json) => GraphEdgeData(
    from: json['from'],
    to: json['to'],
    similarity: (json['similarity'] as num).toDouble(),
  );
}

class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final Graph graph = Graph();
  late final Algorithm builder;

  bool _isLoading = false;
  String _statusMessage = '그래프를 보려면 우측 상단 버튼을 눌러 임베딩을 생성하세요.';

  @override
  void initState() {
    super.initState();
    builder = FruchtermanReingoldAlgorithm(iterations: 1000);
    _loadGraphFromEmbeddingsFile();
  }

  Future<String> _getNotesDirectory() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('홈 디렉토리를 찾을 수 없습니다.');
    return Platform.isMacOS
        ? p.join(home, 'Memordo_Notes')
        : p.join(home, 'Documents', 'Memordo_Notes');
  }

  Future<void> _triggerEmbeddingProcess() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _statusMessage = '로컬 노트 파일을 읽는 중...';
    });

    try {
      final notesDir = await _getNotesDirectory();
      final directory = Directory(notesDir);

      if (!await directory.exists()) {
        _showSnackBar('노트 폴더를 찾을 수 없습니다: $notesDir');
        setState(() {
          _isLoading = false;
          _statusMessage = '노트 폴더를 먼저 생성해주세요.';
        });
        return;
      }

      final files = await _getAllMarkdownFiles(directory);

      if (files.isEmpty) {
        _showSnackBar('노트 폴더에 분석할 .md 파일이 없습니다.');
        setState(() {
          _isLoading = false;
          _statusMessage = '분석할 노트가 없습니다.';
        });
        return;
      }

      List<Map<String, String>> notesData = [];
      for (var file in files) {
        final fileName = p.relative(file.path, from: notesDir);
        final content = await file.readAsString();
        notesData.add({'fileName': fileName, 'content': content});
      }

      final result = await _extractUserDefinedEdgesAndTopics(notesData);
      final userEdges = result.userEdges;
      final topicNodes = result.topicNodes;

      setState(() {
        _statusMessage =
            'AI 서버에 임베딩 요청 중... (${notesData.length}개 파일)\n이 작업은 몇 분 정도 소요될 수 있습니다.';
      });

      final graphData = await ai_service.generateGraphData(notesData);

      if (graphData != null && graphData['error'] == null) {
        graphData['userEdges'] =
            userEdges
                .map(
                  (e) => {
                    'from': e.from,
                    'to': e.to,
                    'similarity': e.similarity,
                  },
                )
                .toList();

        graphData['userTopics'] = topicNodes.toList();

        final jsonString = jsonEncode(graphData);
        final embeddingsFile = File(p.join(notesDir, 'embeddings.json'));
        await embeddingsFile.writeAsString(jsonString);

        _showSnackBar('임베딩 + 사용자 연결 포함 그래프 생성 완료');
        _buildGraphFromData(graphData);
      } else {
        final errorMsg = graphData?['error'] ?? '알 수 없는 오류';
        _showSnackBar('오류: $errorMsg. 백엔드 서버 로그를 확인하세요.');
        _statusMessage = '그래프 생성에 실패했습니다.';
      }
    } catch (e) {
      _showSnackBar('오류 발생: ${e.toString()}');
      _statusMessage = '오류가 발생했습니다.';
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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

  Future<List<GraphEdgeData>> _extractUserDefinedEdges(
    List<Map<String, String>> notesData,
  ) async {
    final userEdges = <GraphEdgeData>[];

    for (final note in notesData) {
      final fileName = note['fileName']!;
      final content = note['content']!;
      final matches = RegExp(r'<<([^<>]+\.md)>>').allMatches(content);

      for (final match in matches) {
        final target = match.group(1);
        if (target != null && target != fileName) {
          userEdges.add(
            GraphEdgeData(from: fileName, to: target, similarity: 1.0),
          );
        }
      }
    }

    return userEdges;
  }

  Future<void> _openNoteEditor(BuildContext context, String filePath) async {
    final notesDir = await _getNotesDirectory();
    final fullPath = p.join(notesDir, filePath);

    final file = File(fullPath);
    if (await file.exists()) {
      final content = await file.readAsString();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MeetingScreen(initialText: content),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('파일을 찾을 수 없습니다: $fullPath'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadGraphFromEmbeddingsFile() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '저장된 임베딩 파일을 찾는 중...';
    });

    final notesDir = await _getNotesDirectory();
    final embeddingsFile = File(p.join(notesDir, 'embeddings.json'));

    if (await embeddingsFile.exists()) {
      try {
        final jsonString = await embeddingsFile.readAsString();
        final data = jsonDecode(jsonString);
        _buildGraphFromData(data);
        _statusMessage = '저장된 데이터로 그래프를 그렸습니다.';
      } catch (e) {
        _statusMessage = '임베딩 파일을 읽는 중 오류 발생: ${e.toString()}';
      }
    } else {
      _statusMessage = '임베딩 파일이 없습니다. 우측 상단 버튼을 눌러 생성해주세요.';
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _buildGraphFromData(Map<String, dynamic> data) {
    graph.nodes.clear();
    graph.edges.clear();

    final List<String> topicIds =
        (data['userTopics'] as List? ?? []).whereType<String>().toList();

    final List<GraphNodeData> nodes =
        (data['nodes'] as List? ?? [])
            .map((nodeJson) => GraphNodeData.fromJson(nodeJson))
            .toList();

    final List<GraphEdgeData> aiEdges =
        (data['edges'] as List? ?? [])
            .map((edgeJson) => GraphEdgeData.fromJson(edgeJson))
            .toList();

    final List<GraphEdgeData> userEdges =
        (data['userEdges'] as List? ?? [])
            .map((edgeJson) => GraphEdgeData.fromJson(edgeJson))
            .toList();

    final nodeMap = <String, Node>{};
    for (var nodeData in nodes) {
      nodeMap[nodeData.id] = Node.Id(nodeData.id);
    }
    for (var topic in topicIds) {
      if (!nodeMap.containsKey(topic)) {
        nodeMap[topic] = Node.Id(topic);
      }
    }

    if (nodes.isEmpty) {
      _statusMessage = '표시할 노트가 없습니다.';
      return;
    }

    for (var edgeData in aiEdges) {
      final fromNode = nodeMap[edgeData.from];
      final toNode = nodeMap[edgeData.to];
      if (fromNode != null && toNode != null) {
        final strokeWidth = 1.0 + (edgeData.similarity - 0.75) * 16;
        final paint =
            Paint()
              ..color = Colors.grey.withOpacity(edgeData.similarity)
              ..strokeWidth = strokeWidth.clamp(1.0, 5.0);
        graph.addEdge(fromNode, toNode, paint: paint);
      }
    }

    for (var edgeData in userEdges) {
      final fromNode = nodeMap[edgeData.from];
      final toNode = nodeMap[edgeData.to];
      if (fromNode != null && toNode != null) {
        final paint =
            Paint()
              ..color = Colors.blue
              ..strokeWidth = 2.5;
        graph.addEdge(fromNode, toNode, paint: paint);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Widget _buildNodeWidget(String label) {
    final isMdFile = label.toLowerCase().endsWith('.md');

    return GestureDetector(
      onTap: () {
        if (isMdFile) {
          _openNoteEditor(context, label);
        } else {
          _showSnackBar('주제 노드: "$label" (클릭 동작 없음)');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMdFile ? Colors.blue.shade400 : Colors.green.shade400,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          p.basenameWithoutExtension(label),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      // Scaffold 대신 Column 반환
      children: [
        AppBar(
          // GraphPage 전용 AppBar
          title: const Text('AI 노트 관계도'),
          actions: [
            IconButton(
              icon: const Icon(Icons.hub_rounded),
              tooltip: '임베딩 생성 및 새로고침',
              onPressed: _triggerEmbeddingProcess,
            ),
          ],
        ),
        Expanded(
          child: Center(
            child:
                _isLoading
                    ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          _statusMessage,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                    : graph.nodeCount() == 0
                    ? Text(
                      _statusMessage,
                      style: Theme.of(context).textTheme.titleMedium,
                    )
                    : InteractiveViewer(
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(100),
                      minScale: 0.01,
                      maxScale: 5.0,
                      child: GraphView(
                        graph: graph,
                        algorithm: builder,
                        paint:
                            Paint()
                              ..color = Colors.grey
                              ..strokeWidth = 1
                              ..style = PaintingStyle.stroke,
                        builder: (Node node) {
                          final label = node.key!.value as String;
                          return _buildNodeWidget(label);
                        },
                      ),
                    ),
          ),
        ),
      ],
    );
  }
}

Future<({List<GraphEdgeData> userEdges, Set<String> topicNodes})>
_extractUserDefinedEdgesAndTopics(List<Map<String, String>> notesData) async {
  final userEdges = <GraphEdgeData>[];
  final topicNodes = <String>{};

  for (final note in notesData) {
    final fileName = note['fileName']!;
    final content = note['content']!;
    final matches = RegExp(r'<<([^<>]+)>>').allMatches(content);

    for (final match in matches) {
      final target = match.group(1)?.trim();
      if (target != null && target.isNotEmpty && target != fileName) {
        userEdges.add(
          GraphEdgeData(from: fileName, to: target, similarity: 1.0),
        );
        topicNodes.add(target);
      }
    }
  }

  return (userEdges: userEdges, topicNodes: topicNodes);
}
