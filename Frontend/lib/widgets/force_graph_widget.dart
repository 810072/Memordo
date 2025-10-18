// lib/widgets/force_graph_widget.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// --- 데이터 모델 ---
class GraphNode {
  final String id;
  final int linkCount;
  GraphNode({required this.id, this.linkCount = 0});
}

class GraphLink {
  final String sourceId;
  final String targetId;
  final double strength;
  GraphLink({
    required this.sourceId,
    required this.targetId,
    this.strength = 1.0,
  });
}

// --- 물리 시뮬레이션 엔진 ---
class ForceNode {
  final String id;
  Offset position;
  Offset velocity;
  Offset acceleration;
  double mass;
  bool isDragging;
  final int linkCount;

  ForceNode({required this.id, required this.position, this.linkCount = 0})
    : velocity = Offset.zero,
      acceleration = Offset.zero,
      mass = 1.0 + linkCount * 0.2,
      isDragging = false;

  void applyForce(Offset force) {
    if (isDragging) return;
    acceleration += force / mass;
  }

  void update(double damping) {
    if (!isDragging) {
      velocity += acceleration;
      velocity *= damping;
      position += velocity;
    }
    acceleration = Offset.zero;
  }
}

class ForceLink {
  final ForceNode source;
  final ForceNode target;
  final double strength;

  ForceLink({required this.source, required this.target, this.strength = 1.0});
}

class ForceSimulation {
  List<ForceNode> nodes;
  List<ForceLink> links;
  Size canvasSize;

  final double centerStrength;
  final double linkDistance;
  final double chargeStrength;

  double linkStrength = 0.3;
  double collisionRadius;
  double damping = 0.85;
  double alpha = 1.0;
  double alphaMin = 0.001;
  double alphaDecay = 0.0228;

  ForceSimulation({
    required this.nodes,
    required this.links,
    required this.canvasSize,
  }) : collisionRadius = 20.0 + (nodes.length / 50).clamp(0, 40),
       linkDistance = 250.0,
       chargeStrength = -50000.0,
       centerStrength = 0.07;

  bool get isActive => alpha > alphaMin;

  void tick() {
    if (!isActive) return;

    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);

    for (var node in nodes) {
      final toCenter = center - node.position;
      node.applyForce(toCenter * centerStrength * alpha);
    }

    for (var link in links) {
      final dx = link.target.position.dx - link.source.position.dx;
      final dy = link.target.position.dy - link.source.position.dy;
      final distance = max(1.0, sqrt(dx * dx + dy * dy));
      final force =
          (distance - linkDistance) *
          linkStrength *
          link.strength *
          alpha /
          distance;
      final f = Offset(dx * force, dy * force);
      link.source.applyForce(f);
      link.target.applyForce(-f);
    }

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final nodeA = nodes[i];
        final nodeB = nodes[j];
        final dx = nodeB.position.dx - nodeA.position.dx;
        final dy = nodeB.position.dy - nodeA.position.dy;
        final distanceSq = dx * dx + dy * dy;
        if (distanceSq < 1) continue;
        final force = chargeStrength * alpha / distanceSq;
        final f = Offset(dx, dy) * (force / sqrt(distanceSq));
        nodeA.applyForce(f);
        nodeB.applyForce(-f);
      }
    }

    for (var node in nodes) {
      node.update(damping);
    }

    alpha += (alphaMin - alpha) * alphaDecay;
  }

  void reheat() => alpha = 1.0;
  void updateCanvasSize(Size newSize) => canvasSize = newSize;
}

// --- ForceGraphView 위젯 ---
class ForceGraphView extends StatefulWidget {
  final List<GraphNode> nodes;
  final List<GraphLink> links;
  final Size canvasSize;
  final Widget Function(BuildContext, GraphNode, Offset) nodeBuilder;
  final Map<String, Map<String, double>>? initialPositions;
  final Function(Map<String, Offset>)? onLayoutStabilized;

  // ✨ [추가] 연결선 커스터마이징 파라미터
  final Color linkColor;
  final double linkOpacity;
  final double linkWidth;

  const ForceGraphView({
    Key? key,
    required this.nodes,
    required this.links,
    required this.canvasSize,
    required this.nodeBuilder,
    this.initialPositions,
    this.onLayoutStabilized,
    this.linkColor = Colors.grey,
    this.linkOpacity = 0.4,
    this.linkWidth = 1.5,
  }) : super(key: key);

  @override
  _ForceGraphViewState createState() => _ForceGraphViewState();
}

class _ForceGraphViewState extends State<ForceGraphView>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  ForceSimulation? _simulation;
  final TransformationController _transformationController =
      TransformationController();
  ForceNode? _draggedNode;

  @override
  void initState() {
    super.initState();
    _initializeSimulation();
    _ticker = createTicker((_) {
      if (_simulation?.isActive ?? false) {
        setState(() {
          _simulation!.tick();
        });
      } else {
        _ticker.stop();
        if (widget.onLayoutStabilized != null) {
          final finalPositions = {
            for (var node in _simulation!.nodes) node.id: node.position,
          };
          widget.onLayoutStabilized!(finalPositions);
        }
      }
    });
    _ticker.start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        const double initialScale = 1.0;
        final viewSize = widget.canvasSize;

        final x = (viewSize.width / 2) - (viewSize.width / 2 * initialScale);
        final y = (viewSize.height / 2) - (viewSize.height / 2 * initialScale);

        final matrix =
            Matrix4.identity()
              ..translate(x, y)
              ..scale(initialScale);

        _transformationController.value = matrix;
      }
    });
  }

  @override
  void didUpdateWidget(ForceGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nodes != oldWidget.nodes || widget.links != oldWidget.links) {
      _updateSimulation();
      if (!_ticker.isActive) {
        _ticker.start();
      }
    } else if (widget.canvasSize != oldWidget.canvasSize) {
      _simulation?.updateCanvasSize(widget.canvasSize);
      _simulation?.reheat();
      if (!_ticker.isActive) {
        _ticker.start();
      }
    }
  }

  void _updateSimulation() {
    if (_simulation == null) {
      _initializeSimulation();
      return;
    }

    final oldPositions = {
      for (var node in _simulation!.nodes) node.id: node.position,
    };

    final random = Random();

    final forceNodes =
        widget.nodes.map((n) {
          final initialPosition = widget.initialPositions?[n.id];
          return ForceNode(
            id: n.id,
            position:
                initialPosition != null
                    ? Offset(initialPosition['dx']!, initialPosition['dy']!)
                    : oldPositions[n.id] ??
                        Offset(
                          widget.canvasSize.width / 2 +
                              (random.nextDouble() - 0.5) * 100,
                          widget.canvasSize.height / 2 +
                              (random.nextDouble() - 0.5) * 100,
                        ),
            linkCount: n.linkCount,
          );
        }).toList();

    final nodeMap = {for (var n in forceNodes) n.id: n};
    final forceLinks =
        widget.links
            .where(
              (l) =>
                  nodeMap.containsKey(l.sourceId) &&
                  nodeMap.containsKey(l.targetId),
            )
            .map(
              (l) => ForceLink(
                source: nodeMap[l.sourceId]!,
                target: nodeMap[l.targetId]!,
                strength: l.strength,
              ),
            )
            .toList();

    _simulation!.nodes = forceNodes;
    _simulation!.links = forceLinks;
    _simulation!.reheat();
  }

  void _initializeSimulation() {
    final random = Random();
    final forceNodes =
        widget.nodes.map((n) {
          final initialPosition = widget.initialPositions?[n.id];
          return ForceNode(
            id: n.id,
            position:
                initialPosition != null
                    ? Offset(initialPosition['dx']!, initialPosition['dy']!)
                    : Offset(
                      widget.canvasSize.width / 2 +
                          (random.nextDouble() - 0.5) * 100,
                      widget.canvasSize.height / 2 +
                          (random.nextDouble() - 0.5) * 100,
                    ),
            linkCount: n.linkCount,
          );
        }).toList();

    final nodeMap = {for (var n in forceNodes) n.id: n};
    final forceLinks =
        widget.links
            .where(
              (l) =>
                  nodeMap.containsKey(l.sourceId) &&
                  nodeMap.containsKey(l.targetId),
            )
            .map(
              (l) => ForceLink(
                source: nodeMap[l.sourceId]!,
                target: nodeMap[l.targetId]!,
                strength: l.strength,
              ),
            )
            .toList();

    _simulation = ForceSimulation(
      nodes: forceNodes,
      links: forceLinks,
      canvasSize: widget.canvasSize,
    );
    _simulation?.reheat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_simulation == null) {
      return const Center(child: CircularProgressIndicator());
    }

    _simulation!.updateCanvasSize(widget.canvasSize);

    return InteractiveViewer(
      transformationController: _transformationController,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.1,
      maxScale: 4.0,
      child: CustomPaint(
        size: widget.canvasSize,
        // ✨ [수정] 연결선 색상 커스터마이징 전달
        painter: _LinkPainter(
          links: _simulation!.links,
          linkColor: widget.linkColor,
          linkOpacity: widget.linkOpacity,
          linkWidth: widget.linkWidth,
        ),
        child: Stack(
          children:
              _simulation!.nodes.map((forceNode) {
                final graphNode = widget.nodes.firstWhere(
                  (n) => n.id == forceNode.id,
                );

                const double widgetWidth = 110;
                const double widgetHeight = 65;

                return Positioned(
                  left: forceNode.position.dx - (widgetWidth / 2),
                  top: forceNode.position.dy - (widgetHeight / 2),
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _draggedNode = forceNode;
                        _draggedNode!.isDragging = true;
                      });
                      _simulation?.reheat();
                      if (!_ticker.isActive) _ticker.start();
                    },
                    onPanUpdate: (details) {
                      if (_draggedNode != null) {
                        setState(() {
                          _draggedNode!.position += details.delta;
                        });
                      }
                    },
                    onPanEnd: (details) {
                      if (_draggedNode != null) {
                        setState(() {
                          _draggedNode!.isDragging = false;
                          _draggedNode = null;
                        });
                        _simulation?.reheat();
                        if (!_ticker.isActive) _ticker.start();
                      }
                    },
                    child: widget.nodeBuilder(
                      context,
                      graphNode,
                      forceNode.position,
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }
}

// ✨ [수정] 연결선 색상 커스터마이징 적용
class _LinkPainter extends CustomPainter {
  final List<ForceLink> links;
  final Color linkColor;
  final double linkOpacity;
  final double linkWidth;

  _LinkPainter({
    required this.links,
    required this.linkColor,
    required this.linkOpacity,
    required this.linkWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = linkColor.withOpacity(linkOpacity)
          ..strokeWidth = linkWidth;

    for (var link in links) {
      canvas.drawLine(link.source.position, link.target.position, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
