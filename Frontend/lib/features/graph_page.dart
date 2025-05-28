// lib/features/graph_page.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_graph_view/flutter_graph_view.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
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

  GraphAlgorithm _getSelectedAlgorithm() {
    return RandomAlgorithm(
      decorators: [
        CoulombDecorator(),
        HookeDecorator(),
        CoulombCenterDecorator(),
        HookeCenterDecorator(),
        ForceDecorator(),
        ForceMotionDecorator(),
        TimeCounterDecorator(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var vertexes = <Map>[];
    var r = Random();
    for (var i = 0; i < 20; i++) {
      vertexes.add({
        'id': 'node$i',
        'tag': 'tag${r.nextInt(9)}',
        'tags': [
          'tag${r.nextInt(9)}',
          if (r.nextBool()) 'tag${r.nextInt(4)}',
          if (r.nextBool()) 'tag${r.nextInt(8)}',
        ],
      });
    }
    var edges = <Map>[];
    for (var i = 0; i < 20; i++) {
      edges.add({
        'srcId': 'node${(i % 8) + 8}',
        'dstId': 'node$i',
        'edgeName': 'edge${r.nextInt(3)}',
        'ranking': DateTime.now().millisecond,
      });
    }
    var data = {'vertexes': vertexes, 'edges': edges};

    return MainLayout(
      // ✅ MainLayout 사용
      activePage: PageType.graph,
      child: Column(
        children: [
          _buildTopBar(), // ✅ 상단 바
          _buildControlPanel(), // ✅ 컨트롤 패널
          Expanded(child: _buildGraphArea(data)), // ✅ 그래프 영역
          // CollapsibleBottomSection 제거
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      // ✅ 수정된 Container
      height: 50,
      // color: Colors.white, // <--- 이 줄 삭제
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white, // <--- color 속성을 BoxDecoration 안으로 이동
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
      // ✅ 수정된 Container
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      // color: Colors.white, // <--- 이 줄 삭제
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: Colors.white, // <--- color 속성을 BoxDecoration 안으로 이동
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
            value:
                _currentAlgorithmType, // _currentAlgorithmType 변수는 State 내에 있어야 함
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
                });
              } // setState 호출
            },
            underline: Container(height: 1, color: Colors.deepPurpleAccent),
            focusColor: Colors.transparent,
          ),
          const SizedBox(width: 40),
          const Text("Zoom:", style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 10),
          Expanded(
            child: Slider(
              value: _scale, // _scale 변수는 State 내에 있어야 함
              min: 0.1,
              max: 2.0,
              divisions: 19,
              label: _scale.toStringAsFixed(1),
              activeColor: Colors.deepPurple.shade400,
              inactiveColor: Colors.deepPurple.shade100,
              onChanged: (double value) {
                // setState 호출
                setState(() {
                  _scale = value;
                  final center =
                      _controller.value
                          .getTranslation(); // _controller는 State 내에 있어야 함
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

  Widget _buildGraphArea(Map data) {
    return Container(
      // ✅ 그래프 영역 스타일 개선
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
              boundaryMargin: const EdgeInsets.all(100), // 여백 조정
              minScale: 0.1,
              maxScale: 5.0,
              child: FlutterGraphWidget(
                data: data,
                algorithm: _getSelectedAlgorithm(),
                convertor: MapConvertor(),
                options:
                    Options()
                      ..enableHit = false
                      ..panelDelay = const Duration(milliseconds: 500)
                      ..graphStyle =
                          (GraphStyle()
                            ..tagColor = {'tag8': Colors.orangeAccent.shade200}
                            ..tagColorByIndex = [
                              Colors.red.shade200,
                              Colors.orange.shade200,
                              Colors.yellow.shade200,
                              Colors.green.shade200,
                              Colors.blue.shade200,
                              Colors.blueAccent.shade200,
                              Colors.purple.shade200,
                              Colors.pink.shade200,
                              Colors.blueGrey.shade200,
                              Colors.deepOrange.shade200,
                            ])
                      ..useLegend = true
                      ..vertexPanelBuilder = vertexPanelBuilder
                      ..edgeShape = EdgeLineShape()
                      ..vertexShape = VertexCircleShape(),
              ),
            );
          },
        ),
      ),
    );
  }

  // ... (vertexPanelBuilder, edgePanelBuilder 동일) ...
  Widget edgePanelBuilder(Edge edge, Viewfinder viewfinder) {
    /* ... */
    return Stack();
  }

  Widget vertexPanelBuilder(dynamic hoverVertex, Viewfinder viewfinder) {
    /* ... */
    return Stack();
  }
}
