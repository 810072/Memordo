import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:graphview/GraphView.dart';
import '../layout/main_layout.dart';
import 'page_type.dart';

enum GraphAlgorithmType { random, fruchtermanReingold }

class GraphPage extends StatefulWidget {
  const GraphPage({super.key});
  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  GraphAlgorithmType _currentAlgorithmType = GraphAlgorithmType.random;
  double _scale = 1.0;
  final TransformationController _controller = TransformationController();

  final Graph graph = Graph();
  late Algorithm _algorithm;
  final Random random = Random();

  @override
  void initState() {
    super.initState();
    _generateGraph();
    _updateAlgorithm();
  }

  void _generateGraph() {
    graph.nodes.clear();
    for (int i = 0; i < 20; i++) {
      graph.addNode(Node.Id('Node $i'));
    }
    for (int i = 0; i < 25; i++) {
      var nodeList = graph.nodes.toList();
      var src = nodeList[random.nextInt(nodeList.length)];
      var dst = nodeList[random.nextInt(nodeList.length)];
      if (src != dst) {
        graph.addEdge(src, dst);
      }
    }
  }

  void _updateAlgorithm() {
    if (_currentAlgorithmType == GraphAlgorithmType.random) {
      _algorithm = FruchtermanReingoldAlgorithm(iterations: 1000);
    } else {
      _algorithm = FruchtermanReingoldAlgorithm(iterations: 1500);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activePage: PageType.graph,
      child: Column(
        children: [
          _buildTopBar(),
          _buildControlPanel(),
          Expanded(child: _buildGraphArea()),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Text(
            'Graph View',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Text(
            'Memo Relationships',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 3,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "Algorithm:",
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 10),
          DropdownButton<GraphAlgorithmType>(
            value: _currentAlgorithmType,
            items: const [
              DropdownMenuItem(
                value: GraphAlgorithmType.random,
                child: Text('Random'),
              ),
              DropdownMenuItem(
                value: GraphAlgorithmType.fruchtermanReingold,
                child: Text('Fruchterman-Reingold'),
              ),
            ],
            onChanged: (GraphAlgorithmType? newValue) {
              if (newValue != null) {
                setState(() {
                  _currentAlgorithmType = newValue;
                  _updateAlgorithm();
                });
              }
            },
            underline: Container(height: 1, color: Colors.deepPurpleAccent),
            focusColor: Colors.transparent,
          ),
          const SizedBox(width: 40),
          const Text("Zoom:", style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 10),
          Expanded(
            child: Slider(
              value: _scale,
              min: 0.1,
              max: 2.0,
              divisions: 19,
              label: _scale.toStringAsFixed(1),
              activeColor: Colors.deepPurple.shade400,
              inactiveColor: Colors.deepPurple.shade100,
              onChanged: (double value) {
                setState(() {
                  _scale = value;
                  final center = _controller.value.getTranslation();
                  _controller.value =
                      vm.Matrix4.identity()
                        ..translate(center.x, center.y)
                        ..scale(_scale);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphArea() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.all(16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            vm.Matrix4 initialTransform =
                vm.Matrix4.identity()
                  ..translate(
                    constraints.maxWidth / 2,
                    constraints.maxHeight / 2,
                  )
                  ..scale(_scale);
            _controller.value = initialTransform;

            return InteractiveViewer(
              transformationController: _controller,
              boundaryMargin: const EdgeInsets.all(100),
              minScale: 0.1,
              maxScale: 5.0,
              child: GraphView(
                graph: graph,
                algorithm: _algorithm,
                builder: (Node node) {
                  return _nodeWidget(node.key!.value);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _nodeWidget(Object? nodeId) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        border: Border.all(color: Colors.blue),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(nodeId.toString()),
    );
  }
}
