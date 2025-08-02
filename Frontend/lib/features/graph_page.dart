import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import './meeting_screen.dart'; // 사용자 정의 위젯
import '../utils/ai_service.dart' as ai_service; // 사용자 정의 서비스
import '../providers/token_status_provider.dart';
import '../auth/login_page.dart';

// 데이터 모델 클래스
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
  late Algorithm builder;

  bool _isLoading = false;
  bool _showUserGraph = false;
  String _statusMessage = '그래프를 보려면 구글 로그인이 필요합니다.';

  static const double _similarityThreshold = 0.8;
  final double _canvasWidth = 4000;
  final double _canvasHeight = 4000;

  List<GraphNodeData> _allNodesData = [];
  List<GraphEdgeData> _aiEdges = [];
  List<GraphEdgeData> _userEdges = [];
  Set<String> _topicIds = {};
  final Map<String, Node> _nodeMap = {};
  Set<String> _activeUserNodeIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tokenProvider = context.read<TokenStatusProvider>();
      if (tokenProvider.isAuthenticated) {
        _loadGraphFromEmbeddingsFile();
      }
    });
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

    _topicIds = (data['userTopics'] as List? ?? []).whereType<String>().toSet();
    _allNodesData =
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

    for (var nodeData in _allNodesData) {
      _nodeMap[nodeData.id] = Node.Id(nodeData.id);
    }
    for (var topic in _topicIds) {
      if (!_nodeMap.containsKey(topic)) {
        _nodeMap[topic] = Node.Id(topic);
      }
    }

    if (_nodeMap.isEmpty) {
      setState(() {
        _statusMessage = '표시할 노트가 없습니다.';
        _isLoading = false;
      });
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

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadGraphFromEmbeddingsFile() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '저장된 임베딩 파일을 찾는 중...';
    });
    try {
      final notesDir = await _getNotesDirectory();
      final embeddingsFile = File(p.join(notesDir, 'embeddings.json'));

      if (await embeddingsFile.exists()) {
        final jsonString = await embeddingsFile.readAsString();
        final data = jsonDecode(jsonString);
        _buildGraphFromData(data);
      } else {
        setState(() {
          _statusMessage = '임베딩 파일이 없습니다. 우측 상단 버튼을 눌러 생성해주세요.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '그래프 파일 로딩 중 오류 발생: $e';
        _isLoading = false;
      });
    }
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
        setState(() => _isLoading = false);
        return;
      }
      final files = await _getAllMarkdownFiles(directory);
      if (files.isEmpty) {
        _showSnackBar('노트 폴더에 분석할 .md 파일이 없습니다.');
        setState(() => _isLoading = false);
        return;
      }

      List<Map<String, String>> notesData = [];
      for (var file in files) {
        final fileName = p.relative(file.path, from: notesDir);
        final content = await file.readAsString();
        notesData.add({'fileName': fileName, 'content': content});
      }

      final result = await _extractUserDefinedEdgesAndTopics(notesData);
      setState(() {
        _statusMessage = 'AI 서버에 임베딩 요청 중... (${notesData.length}개 파일)';
      });

      final graphData = await ai_service.generateGraphData(notesData);
      if (graphData != null && graphData['error'] == null) {
        graphData['userEdges'] =
            result.userEdges
                .map(
                  (e) => {
                    'from': e.from,
                    'to': e.to,
                    'similarity': e.similarity,
                  },
                )
                .toList();
        graphData['userTopics'] = result.topicNodes.toList();

        final jsonString = jsonEncode(graphData);
        final embeddingsFile = File(p.join(notesDir, 'embeddings.json'));
        await embeddingsFile.writeAsString(jsonString);

        _showSnackBar('그래프 생성 완료');
        _buildGraphFromData(graphData);
      } else {
        final errorMsg = graphData?['error'] ?? '알 수 없는 오류';
        _showSnackBar('오류: $errorMsg');
        _statusMessage = '그래프 생성에 실패했습니다.';
      }
    } catch (e) {
      _showSnackBar('오류 발생: ${e.toString()}');
      _statusMessage = '오류가 발생했습니다.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokenProvider = context.watch<TokenStatusProvider>();

    return Column(
      children: [
        AppBar(
          title: const Text('AI 노트 관계도'),
          actions: [
            IconButton(
              icon: const Icon(Icons.hub_rounded),
              tooltip: '임베딩 생성 및 새로고침',
              onPressed:
                  !tokenProvider.isAuthenticated
                      ? null
                      : _triggerEmbeddingProcess,
            ),
            IconButton(
              icon: Icon(_showUserGraph ? Icons.person : Icons.smart_toy),
              tooltip: _showUserGraph ? '사용자 정의 링크 보기' : 'AI 추천 관계 보기',
              onPressed:
                  !tokenProvider.isAuthenticated
                      ? null
                      : () {
                        if (_isLoading || _nodeMap.isEmpty) return;
                        setState(() {
                          _showUserGraph = !_showUserGraph;
                          _updateEdges();
                        });
                      },
            ),
          ],
        ),
        Expanded(
          child: Center(
            child:
                !tokenProvider.isAuthenticated
                    ? _buildLoginPrompt(context)
                    : _isLoading
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
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      minScale: 0.01,
                      maxScale: 5.0,
                      child: SizedBox(
                        width: _canvasWidth,
                        height: _canvasHeight,
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

                            if (_showUserGraph &&
                                !_activeUserNodeIds.contains(label)) {
                              return const SizedBox.shrink();
                            }

                            return _buildNodeWidget(label);
                          },
                        ),
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginPrompt(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 20),
          const Text(
            '로그인이 필요한 기능입니다.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            '노트 관계도를 생성하고 보려면 로그인이 필요합니다.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.login, size: 16),
            label: const Text('로그인 페이지로 이동'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
              ).then((_) {
                final tokenProvider = context.read<TokenStatusProvider>();
                if (tokenProvider.isAuthenticated) {
                  _loadGraphFromEmbeddingsFile();
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<String> _getNotesDirectory() async {
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

  Future<void> _openNoteEditor(BuildContext context, String filePath) async {
    final notesDir = await _getNotesDirectory();
    final fullPath = p.join(notesDir, filePath);
    final file = File(fullPath);

    if (await file.exists()) {
      final content = await file.readAsString();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => Scaffold(
                appBar: AppBar(
                  title: Text(p.basenameWithoutExtension(filePath)),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                body: MeetingScreen(initialText: content, filePath: fullPath),
              ),
        ),
      );
    } else {
      _showSnackBar('파일을 찾을 수 없습니다: $fullPath');
    }
  }
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
