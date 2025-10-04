// lib/features/graph_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import './meeting_screen.dart';
import '../viewmodels/graph_viewmodel.dart';
import '../providers/status_bar_provider.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GraphViewModel>().loadGraphFromEmbeddingsFile();
    });
  }

  Widget _buildNodeWidget(BuildContext context, String label) {
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

  Future<void> _openNoteEditor(BuildContext context, String filePath) async {
    final viewModel = context.read<GraphViewModel>();
    final statusBar = context.read<StatusBarProvider>();
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
        statusBar.showStatusMessage(
          '파일을 찾을 수 없습니다: $fullPath',
          type: StatusType.error,
        );
      }
    } else {
      statusBar.showStatusMessage(
        '주제 노드: "$filePath" (클릭 동작 없음)',
        type: StatusType.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GraphViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  viewModel.isAiGraphView ? 'AI 그래프 분석 중...' : '사용자 노트 스캔 중...',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // ✨ [수정] ViewModel의 상태에 따라 어떤 뷰를 보여줄지 결정
        if (viewModel.isAiGraphView) {
          // --- AI 그래프 뷰 ---
          return viewModel.aiGraph.nodeCount() == 0
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
                    graph: viewModel.aiGraph,
                    algorithm: viewModel.aiGraphBuilder,
                    paint:
                        Paint()
                          ..color = Colors.grey
                          ..strokeWidth = 1
                          ..style = PaintingStyle.stroke,
                    builder: (Node node) {
                      final label = node.key!.value as String;
                      return _buildNodeWidget(context, label);
                    },
                  ),
                ),
              );
        } else {
          // --- 사용자 정의 그래프 뷰 ---
          return viewModel.userGraph.nodeCount() == 0
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
                    graph: viewModel.userGraph,
                    algorithm: viewModel.userGraphBuilder,
                    paint:
                        Paint()
                          ..color =
                              Colors
                                  .transparent // 연결선 없음
                          ..strokeWidth = 1
                          ..style = PaintingStyle.stroke,
                    builder: (Node node) {
                      final label = node.key!.value as String;
                      return _buildNodeWidget(context, label);
                    },
                  ),
                ),
              );
        }
      },
    );
  }
}
