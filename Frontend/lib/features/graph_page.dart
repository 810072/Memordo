// 필요한 라이브러리 및 내부 파일 import
import 'dart:math'; // 랜덤 값 생성을 위한 math 라이브러리 임포트
import 'package:flutter/material.dart';
import 'package:flutter_graph_view/flutter_graph_view.dart'; // 그래프 뷰 라이브러리 임포트
import 'package:vector_math/vector_math_64.dart' as vm; // Matrix4 충돌 방지를 위한 별칭 import
import '../layout/left_sidebar_layout.dart';
import '../layout/bottom_section.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// 그래프 레이아웃 알고리즘 타입을 정의하는 열거형
enum GraphAlgorithmType { random, fruchtermanReingold }

// 그래프 페이지 위젯
class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

// GraphPage 위젯의 상태를 관리하는 클래스
class _GraphPageState extends State<GraphPage> {
  GraphAlgorithmType _currentAlgorithmType = GraphAlgorithmType.random; // 선택된 알고리즘
  double _scale = 1.0; // 그래프 확대 비율
  final TransformationController _controller = TransformationController(); // 확대/이동 제어용 컨트롤러

  // 선택된 알고리즘에 따라 GraphAlgorithm 반환
  GraphAlgorithm _getSelectedAlgorithm() {
    switch (_currentAlgorithmType) {
      case GraphAlgorithmType.random:
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
      case GraphAlgorithmType.fruchtermanReingold:
        // 실제 알고리즘 구현 필요 시 별도 구현 또는 라이브러리 교체 고려
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
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // 노드 및 에지 데이터 생성
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

    return LeftSidebarLayout(
      activePage: PageType.graph,
      child: Column(
        children: [
          _buildTopBar(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                DropdownButton<GraphAlgorithmType>(
                  value: _currentAlgorithmType,
                  items: [
                    DropdownMenuItem(
                      value: GraphAlgorithmType.random,
                      child: const Text('Random'),
                    ),
                    DropdownMenuItem(
                      value: GraphAlgorithmType.fruchtermanReingold,
                      child: const Text('Fruchterman-Reingold'),
                    ),
                  ],
                  onChanged: (GraphAlgorithmType? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _currentAlgorithmType = newValue;
                      });
                    }
                  },
                ),
                SizedBox(
                  width: 200,
                  child: Slider(
                    value: _scale,
                    min: 0.1,
                    max: 2.0,
                    divisions: 20,
                    label: _scale.toStringAsFixed(1),
                    onChanged: (double value) {
                      setState(() {
                        _scale = value;
                        _controller.value = vm.Matrix4.identity()
                          ..translate(200, 200)
                          ..scale(_scale);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildGraphArea(data)),
          const CollapsibleBottomSection(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 50,
      color: Colors.grey[300],
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Text(
        '2025 / 03',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildGraphArea(Map data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        vm.Matrix4 initialTransform = vm.Matrix4.identity()
          ..translate(constraints.maxWidth / 2, constraints.maxHeight / 2)
          ..scale(_scale);
        _controller.value = initialTransform;
        return InteractiveViewer(
          transformationController: _controller,
          boundaryMargin: const EdgeInsets.all(500),
          constrained: true,
          minScale: 0.1,
          maxScale: 5.0,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: FlutterGraphWidget(
              data: data,
              algorithm: _getSelectedAlgorithm(),
              convertor: MapConvertor(),
              options: Options()
                ..enableHit = false
                ..panelDelay = const Duration(milliseconds: 500)
                ..graphStyle = (GraphStyle()
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
          ),
        );
      },
    );
  }

  Widget edgePanelBuilder(Edge edge, Viewfinder viewfinder) {
    var c = viewfinder.localToGlobal(edge.position);
    return Stack(
      children: [
        Positioned(
          left: c.x + 5,
          top: c.y,
          child: SizedBox(
            width: 200,
            child: ColoredBox(
              color: Colors.grey.shade900.withAlpha(200),
              child: ListTile(
                title: Text(
                  '${edge.edgeName} @${edge.ranking}\nDelay: 500ms',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget vertexPanelBuilder(dynamic hoverVertex, Viewfinder viewfinder) {
    var c = viewfinder.localToGlobal(hoverVertex.cpn!.position);
    return Stack(
      children: [
        Positioned(
          left: c.x + hoverVertex.radius + 5,
          top: c.y - 20,
          child: SizedBox(
            width: 120,
            child: ColoredBox(
              color: Colors.grey.shade900.withAlpha(200),
              child: ListTile(
                title: Text(
                  'Id: ${hoverVertex.id}',
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  'Tag: ${hoverVertex.data['tag']}\nDegree: ${hoverVertex.degree} ${hoverVertex.prevVertex?.id ?? ""}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
