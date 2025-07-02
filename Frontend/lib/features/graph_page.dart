import 'dart:io';
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:path/path.dart' as p;

import '../layout/left_sidebar_content.dart';
import '../layout/right_sidebar_content.dart';
import '../layout/main_layout.dart';
import 'page_type.dart';

class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final Graph graph = Graph();
  final Map<String, Node> nodeMap = {};
  late final Algorithm builder;

  @override
  void initState() {
    super.initState();
    builder = FruchtermanReingoldAlgorithm(iterations: 1000);
    _buildGraphFromNotes();
  }

  Future<void> _buildGraphFromNotes() async {
    final notesDir = await _getNotesDirectory();
    final files = Directory(
      notesDir,
    ).listSync().where((f) => f is File && p.extension(f.path) == '.md');

    for (final file in files) {
      final fileName = p.basenameWithoutExtension(file.path);
      final content = await File(file.path).readAsString();

      final fromNode = nodeMap.putIfAbsent(fileName, () => Node.Id(fileName));

      final matches = RegExp(r'<<(.+?)>>').allMatches(content);
      for (final match in matches) {
        final targetName = match.group(1)!.trim();
        if (targetName.isEmpty || targetName == fileName) continue;

        final toNode = nodeMap.putIfAbsent(
          targetName,
          () => Node.Id(targetName),
        );
        graph.addEdge(fromNode, toNode);
      }
    }

    setState(() {});
  }

  Future<String> _getNotesDirectory() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('홈 디렉토리를 찾을 수 없습니다.');

    return Platform.isMacOS
        ? p.join(home, 'Memordo_Notes')
        : p.join(home, 'Documents', 'Memordo_Notes');
  }

  Widget _buildNodeWidget(String label) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.lightBlueAccent,
        border: Border.all(color: Colors.blue),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activePage: PageType.graph, // 현재 페이지를 '그래프'로 설정
      child: Scaffold(
        appBar: AppBar(title: const Text('노트 그래프')),
        body:
            graph.nodeCount() == 0
                ? const Center(child: Text('노드를 불러오는 중이거나 연결된 노드가 없습니다.'))
                : InteractiveViewer(
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(100),
                  minScale: 0.01,
                  maxScale: 5,
                  child: GraphView(
                    graph: graph,
                    algorithm: builder,
                    builder: (Node node) {
                      final label = node.key!.value as String;
                      return _buildNodeWidget(label);
                    },
                  ),
                ),
      ),
    );
  }
}
