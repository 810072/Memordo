// lib/features/graph_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../providers/tab_provider.dart';
import '../viewmodels/graph_viewmodel.dart';
import '../providers/status_bar_provider.dart';
import '../widgets/force_graph_widget.dart';

// --- ✨ [추가] 필요한 import ---
import '../widgets/custom_popup_menu.dart';
import '../providers/file_system_provider.dart';
import '../layout/bottom_section_controller.dart';
import '../utils/ai_service.dart';
import '../model/file_system_entry.dart';
// --- ✨ [추가] ---

export '../viewmodels/graph_viewmodel.dart'; // [기존 코드]

class GraphPage extends StatefulWidget {
  const GraphPage({super.key});
  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  String? _hoveredNodeId;
  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = context.read<GraphViewModel>();
      viewModel.buildUserGraph();
    });
  }

  double _getNodeSize(GraphNode node, GraphViewModel viewModel) {
    final linkCount = viewModel.getNodeLinkCount(node.id);
    return 10.0 + (linkCount * 1.5).clamp(0.0, 10.0);
  }

  Color _getNodeColor(GraphNode node, GraphViewModel viewModel) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_selectedNodeId == node.id) return Colors.blue.shade400;
    if (_hoveredNodeId == node.id)
      return isDark ? Colors.white70 : Colors.black87;

    if (!viewModel.isAiGraphView) {
      final linkCount = viewModel.getNodeLinkCount(node.id);
      if (linkCount == 0)
        return isDark ? Colors.grey.shade700 : Colors.grey.shade400;
      if (linkCount < 3)
        return isDark ? Colors.grey.shade600 : Colors.grey.shade500;
      if (linkCount < 6)
        return isDark ? Colors.blue.shade700 : Colors.blue.shade400;
      return isDark ? Colors.purple.shade600 : Colors.purple.shade400;
    }

    return isDark ? Colors.grey.shade600 : Colors.grey.shade500;
  }

  // --- ✨ [추가] AI 요약 실행 함수 ---
  Future<void> _triggerAISummary(BuildContext context, GraphNode node) async {
    final bottomController = context.read<BottomSectionController>();
    final statusBar = context.read<StatusBarProvider>();
    final viewModel = context.read<GraphViewModel>();

    if (bottomController.isLoading) return;

    try {
      bottomController.setIsLoading(true);
      final nodeName = p.basenameWithoutExtension(node.id);
      bottomController.updateSummary('AI가 \'$nodeName\' 노트를 요약 중입니다...');

      final notesDir = await viewModel.getNotesDirectory();
      final fullPath = p.join(notesDir, node.id);
      final content = await File(fullPath).readAsString();

      if (content.trim().length < 50) {
        throw Exception('요약할 내용이 너무 짧습니다 (최소 50자 필요).');
      }

      final summary = await callBackendTask(
        taskType: "summarize",
        text: content,
      );

      if (summary == null || summary.contains("오류") || summary.contains("실패")) {
        throw Exception(summary ?? '요약에 실패했거나 내용이 없습니다.');
      }

      if (!mounted) return; // 비동기 작업 후 mounted 확인
      bottomController.updateSummary(summary);
      statusBar.showStatusMessage(
        '\'$nodeName\' 노트 요약 완료 ✅',
        type: StatusType.success,
      );
    } catch (e) {
      final errorMessage = e.toString().replaceFirst("Exception: ", "");
      if (mounted) {
        bottomController.updateSummary('요약 중 오류 발생: $errorMessage');
        statusBar.showStatusMessage(
          '요약 중 오류 발생: $errorMessage',
          type: StatusType.error,
        );
      }
    } finally {
      if (mounted) {
        bottomController.setIsLoading(false);
      }
    }
  }

  // --- ✨ [추가] 우클릭 컨텍스트 메뉴 표시 함수 ---
  void _showNodeContextMenu(
    BuildContext context,
    Offset position,
    GraphNode node,
  ) async {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final fileSystemProvider = context.read<FileSystemProvider>();
    final viewModel = context.read<GraphViewModel>();

    // 삭제 기능을 위해 임시 FileSystemEntry 객체 생성
    final notesDir = await viewModel.getNotesDirectory();
    final fullPath = p.join(notesDir, node.id);
    final entry = FileSystemEntry(
      name: p.basename(node.id),
      path: fullPath,
      isDirectory: false,
    );

    showInstantMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 120),
      items: <PopupMenuEntry<String>>[
        CompactPopupMenuItem<String>(
          value: 'summarize',
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 14,
                color: isDarkMode ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 8),
              const Text('AI 요약'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1.0),
        CompactPopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400),
              const SizedBox(width: 8),
              Text('삭제', style: TextStyle(color: Colors.red.shade400)),
            ],
          ),
        ),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300,
          width: 1.0,
        ),
      ),
      color: isDarkMode ? const Color(0xFF2E2E2E) : theme.cardColor,
    ).then((String? value) async {
      if (value == 'summarize') {
        _triggerAISummary(context, node);
      } else if (value == 'delete') {
        final bool success = await fileSystemProvider.deleteEntry(
          context,
          entry,
        );
        if (success && mounted) {
          // 삭제 성공 시 그래프를 새로고침
          viewModel.buildUserGraph();
        }
      }
    });
  }

  // --- ✨ [수정] _buildNodeWidget 함수 ---
  Widget _buildNodeWidget(
    BuildContext context,
    GraphNode node,
    Offset position,
  ) {
    final viewModel = context.read<GraphViewModel>();
    final nodeSize = _getNodeSize(node, viewModel);
    final nodeColor = _getNodeColor(node, viewModel);
    final isSelected = _selectedNodeId == node.id;
    final isHovered = _hoveredNodeId == node.id;
    final label = p.basenameWithoutExtension(node.id);

    final double widgetWidth = 110;
    final double widgetHeight = 65;

    final double textTopPosition = (widgetHeight / 2) + (nodeSize / 2) + 3;

    return SizedBox(
      width: widgetWidth,
      height: widgetHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // ✨ [수정] MouseRegion을 GestureDetector로 감싸서 우클릭(onSecondaryTapUp) 이벤트를 처리
          GestureDetector(
            onSecondaryTapUp: (details) {
              _showNodeContextMenu(context, details.globalPosition, node);
            },
            child: MouseRegion(
              onEnter: (_) => setState(() => _hoveredNodeId = node.id),
              onExit: (_) => setState(() => _hoveredNodeId = null),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedNodeId =
                        _selectedNodeId == node.id ? null : node.id;
                  });
                  _openNoteInTab(context, node.id);
                },
                child: Container(
                  width: nodeSize,
                  height: nodeSize,
                  decoration: BoxDecoration(
                    color: nodeColor,
                    shape: BoxShape.circle,
                    border:
                        isSelected
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                    boxShadow:
                        isHovered || isSelected
                            ? [
                              BoxShadow(
                                color: nodeColor.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ]
                            : null,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: textTopPosition,
            child: SizedBox(
              width: widgetWidth,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isHovered || isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                  color: (Theme.of(context).textTheme.bodyMedium?.color ??
                          Colors.black)
                      .withOpacity(isHovered || isSelected ? 1.0 : 0.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNoteInTab(BuildContext context, String filePath) async {
    final viewModel = context.read<GraphViewModel>();
    final statusBar = context.read<StatusBarProvider>();
    try {
      final notesDir = await viewModel.getNotesDirectory();
      final fullPath = p.join(notesDir, filePath);
      final file = File(fullPath);

      if (await file.exists()) {
        final content = await file.readAsString();
        if (!mounted) return;
        context.read<TabProvider>().openNewTab(
          filePath: fullPath,
          content: content,
        );
      } else {
        statusBar.showStatusMessage(
          '파일을 찾을 수 없습니다: $fullPath',
          type: StatusType.error,
        );
      }
    } catch (e) {
      statusBar.showStatusMessage('파일을 여는 중 오류 발생: $e', type: StatusType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GraphViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(viewModel.statusMessage),
              ],
            ),
          );
        }

        if (viewModel.nodes.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  viewModel.statusMessage,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                ForceGraphView(
                  key: ValueKey(viewModel.isAiGraphView),
                  nodes: viewModel.nodes,
                  links: viewModel.links,
                  initialPositions: viewModel.nodePositions,
                  onLayoutStabilized: viewModel.updateAndSaveAllNodePositions,
                  canvasSize: Size(constraints.maxWidth, constraints.maxHeight),
                  nodeBuilder: _buildNodeWidget,
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      viewModel.isAiGraphView ? 'AI 추천 관계' : '사용자 정의 링크',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (!viewModel.isAiGraphView)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLegendItem('고립된 노트', Colors.grey.shade600),
                          _buildLegendItem('연결 1-2개', Colors.grey.shade500),
                          _buildLegendItem('연결 3-5개', Colors.blue.shade400),
                          _buildLegendItem('연결 6개 이상', Colors.purple.shade400),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
