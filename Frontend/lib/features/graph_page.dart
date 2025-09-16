// lib/features/graph_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import './meeting_screen.dart';
import '../viewmodels/graph_viewmodel.dart';

// --- 데이터 모델 클래스 (기존과 동일) ---
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

// --- GraphPage 위젯 ---
class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  // ✨ [추가] initState에서 데이터 로딩 시작
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GraphViewModel>().loadGraphFromEmbeddingsFile();
    });
  }

  // ✨ [추가] UI 렌더링 로직을 페이지 위젯으로 다시 이동
  Widget _buildNodeWidget(BuildContext context, String label) {
    final viewModel = context.read<GraphViewModel>();
    final isMdFile = label.toLowerCase().endsWith('.md');

    return GestureDetector(
      onTap: () => _openNoteEditor(context, label),
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

  Future<void> _openNoteEditor(BuildContext context, String filePath) async {
    final viewModel = context.read<GraphViewModel>();
    final isMdFile = filePath.toLowerCase().endsWith('.md');

    if (isMdFile) {
      final notesDir = await viewModel.getNotesDirectory();
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
    } else {
      _showSnackBar('주제 노드: "$filePath" (클릭 동작 없음)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GraphViewModel>(
      builder: (context, viewModel, child) {
        return viewModel.isLoading
            ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    viewModel.statusMessage,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
            : viewModel.graph.nodeCount() == 0
            ? Center(
              child: Text(
                viewModel.statusMessage,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
            : InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              minScale: 0.01,
              maxScale: 5.0,
              child: SizedBox(
                width: viewModel.canvasWidth,
                height: viewModel.canvasHeight,
                child: GraphView(
                  graph: viewModel.graph,
                  algorithm: viewModel.builder,
                  paint:
                      Paint()
                        ..color = Colors.grey
                        ..strokeWidth = 1
                        ..style = PaintingStyle.stroke,
                  builder: (Node node) {
                    final label = node.key!.value as String;
                    if (viewModel.showUserGraph &&
                        !viewModel.isUserNodeActive(label)) {
                      return const SizedBox.shrink();
                    }
                    // ✨ [수정] ViewModel 대신 지역 메서드 호출
                    return _buildNodeWidget(context, label);
                  },
                ),
              ),
            );
      },
    );
  }
}
