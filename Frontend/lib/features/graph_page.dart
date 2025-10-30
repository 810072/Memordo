// lib/features/graph_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../providers/tab_provider.dart';
import '../viewmodels/graph_viewmodel.dart';
import '../viewmodels/graph_customization_settings.dart';
import '../providers/status_bar_provider.dart';
import '../widgets/force_graph_widget.dart';
import '../widgets/custom_popup_menu.dart';
import '../providers/file_system_provider.dart';
import '../layout/bottom_section_controller.dart';
import '../utils/ai_service.dart';
import '../model/file_system_entry.dart';

export '../viewmodels/graph_viewmodel.dart';

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
      final customSettings = context.read<GraphCustomizationSettings>();

      customSettings.loadSettings();
      // buildUserGraph가 호출되면 내부에서 startWatching()도 호출됨
      viewModel.buildUserGraph();
    });
  }

  @override
  void dispose() {
    // ViewModel의 dispose에서 stopWatching 호출
    // context.read<GraphViewModel>().stopWatching();
    super.dispose();
  }

  double _getNodeSize(GraphNode node, GraphViewModel viewModel) {
    final linkCount = viewModel.getNodeLinkCount(node.id);
    return 10.0 + (linkCount * 1.5).clamp(0.0, 10.0);
  }

  Color _getNodeColor(GraphNode node, GraphViewModel viewModel) {
    final customSettings = context.read<GraphCustomizationSettings>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_selectedNodeId == node.id) return Colors.blue.shade400;
    if (_hoveredNodeId == node.id) {
      return isDark ? Colors.white70 : Colors.black87;
    }

    // --- ✨ [수정] AI 그래프 뷰 색상 적용 방식 변경 ---
    // AI 뷰와 사용자 뷰 모두 연결 개수 기반 색상 사용
    final linkCount = viewModel.getNodeLinkCount(node.id);
    return customSettings.getNodeColorByLinks(linkCount, isDark);
    /* // 이전 로직 주석 처리
    if (viewModel.isAiGraphView) {
      return isDark ? Colors.grey.shade600 : Colors.grey.shade500;
    } else {
      final linkCount = viewModel.getNodeLinkCount(node.id);
      return customSettings.getNodeColorByLinks(linkCount, isDark);
    }
    */
    // ---
  }

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

      if (!mounted) return;
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

  void _showNodeContextMenu(
    BuildContext context,
    Offset position,
    GraphNode node,
  ) async {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final fileSystemProvider = context.read<FileSystemProvider>();
    final viewModel = context.read<GraphViewModel>();

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
        // 삭제 후 그래프 뷰 갱신을 위해 ViewModel 함수 호출 고려
        final bool success = await fileSystemProvider.deleteEntry(
          context,
          entry,
        );
        // if (success) {
        //   viewModel.buildUserGraph(); // 삭제 성공 시 그래프 다시 빌드
        // }
      }
    });
  }

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
      // filePath는 이미 상대 경로이므로 그대로 사용
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
        final customSettings = context.watch<GraphCustomizationSettings>();
        if (viewModel.isLoading && viewModel.nodes.isEmpty) {
          // 로딩 중인데 노드가 없으면 로딩 표시
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

        if (viewModel.nodes.isEmpty && !viewModel.isLoading) {
          // 로딩 끝났는데 노드 없으면 빈 상태 표시
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  viewModel.statusMessage, // '표시할 노트가 없습니다.' 등
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }

        // 노드가 있으면 그래프 표시 (로딩 중에도 기존 그래프는 보여줌)
        return LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              color: customSettings.backgroundColor,
              child: Stack(
                children: [
                  // --- ✨ [수정] ForceGraphView에 ValueKey 추가 ---
                  ForceGraphView(
                    key: ValueKey(
                      '${viewModel.isAiGraphView}-${viewModel.nodes.length}-${viewModel.links.length}',
                    ), // 뷰 상태, 노드/링크 수 변경 시 위젯 재생성
                    nodes: viewModel.nodes,
                    links: viewModel.links,
                    initialPositions: viewModel.nodePositions,
                    onLayoutStabilized: viewModel.updateAndSaveAllNodePositions,
                    canvasSize: Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ),
                    nodeBuilder: _buildNodeWidget,
                    linkColor: customSettings.linkColor,
                    linkOpacity: customSettings.linkOpacity,
                    linkWidth: customSettings.linkWidth,
                  ),
                  // ---

                  // --- ✨ [수정] 상단 상태 표시 텍스트 ---
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            viewModel.isAiGraphView
                                ? 'AI 추천 관계'
                                : '사용자 정의 링크', // 상태에 따라 텍스트 변경
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          // 사용자 뷰일 때만 '실시간' 표시
                          if (!viewModel.isAiGraphView) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.visibility,
                              size: 16,
                              color: Colors.green.shade400,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '실시간',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade400,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // ---

                  // --- 범례 (사용자 뷰일 때만 표시) ---
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
                            _buildLegendItem(
                              '고립된 노트',
                              customSettings.isolatedNodeColor,
                            ),
                            _buildLegendItem(
                              '연결 1-2개',
                              customSettings.lowConnectionColor,
                            ),
                            _buildLegendItem(
                              '연결 3-5개',
                              customSettings.mediumConnectionColor,
                            ),
                            _buildLegendItem(
                              '연결 6개 이상',
                              customSettings.highConnectionColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // ---

                  // --- ✨ [수정] 토글 버튼 및 새로고침 버튼 ---
                  Positioned(
                    top: 10,
                    right: 16,
                    child: Column(
                      // Column으로 묶기
                      children: [
                        // 1. 뷰 토글 버튼
                        Tooltip(
                          message:
                              viewModel.isAiGraphView
                                  ? '사용자 링크 보기'
                                  : 'AI 추천 관계 보기',
                          child: IconButton(
                            icon:
                                (viewModel.isLoading &&
                                        !viewModel
                                            .isAiGraphView) // AI 뷰로 전환 중일 때
                                    ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                    : Icon(
                                      viewModel.isAiGraphView
                                          ? Icons
                                              .link // 사용자 링크 아이콘
                                          : Icons
                                              .auto_awesome_outlined, // AI 추천 아이콘
                                    ),
                            onPressed:
                                viewModel.isLoading
                                    ? null
                                    : () => viewModel.toggleGraphView(context),
                          ),
                        ),
                        // 2. AI 뷰일 때만 새로고침 버튼 표시
                        if (viewModel.isAiGraphView)
                          Tooltip(
                            message: 'AI 추천 관계 새로고침',
                            child: IconButton(
                              icon:
                                  (viewModel.isLoading) // AI 뷰에서 로딩 중일 때
                                      ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                      : const Icon(Icons.refresh), // 새로고침 아이콘
                              onPressed:
                                  viewModel.isLoading
                                      ? null // 로딩 중 비활성화
                                      : () => viewModel.loadAiGraph(
                                        context,
                                      ), // AI 그래프 다시 로드
                            ),
                          ),
                      ],
                    ),
                  ),
                  // ---
                ],
              ),
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
