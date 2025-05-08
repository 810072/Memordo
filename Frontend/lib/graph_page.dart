import 'dart:math'; // 랜덤 값 생성을 위한 math 라이브러리 임포트
import 'package:flutter/material.dart';
import 'package:flutter_graph_view/flutter_graph_view.dart'; // 그래프 뷰 라이브러리 임포트
import 'left_sidebar_layout.dart'; // 좌측 사이드바 레이아웃 임포트
import 'bottom_section.dart'; // 하단 액션 영역 위젯 임포트

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
  // 현재 선택된 그래프 레이아웃 알고리즘 타입
  GraphAlgorithmType _currentAlgorithmType = GraphAlgorithmType.random;
  // 그래프 스케일 (슬라이더로 조절)
  double _scale = 1.0;

  // TransformationController를 선언해 InteractiveViewer에 초기 변환 적용 및 관리를 위해 사용
  final TransformationController _controller = TransformationController();

  // 선택된 알고리즘 타입에 따라 해당 그래프 알고리즘 객체를 반환하는 함수
  GraphAlgorithm _getSelectedAlgorithm() {
    switch (_currentAlgorithmType) {
      case GraphAlgorithmType.random:
        // Random 알고리즘에 필요한 데코레이터 설정
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
        // flutter_graph_view 1.1.4에는 FruchtermanReingoldAlgorithm이 없으므로 대체합니다.
        // (실제 Fruchterman-Reingold 알고리즘 구현이 필요하면 해당 라이브러리 업데이트 또는 다른 라이브러리 고려)
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
      default:
        // 기본 알고리즘 (Random)
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
    // 초기 스케일 및 중앙 정렬을 위한 초기 변환 설정
    // (나중에 LayoutBuilder로 영역 크기에 따라 업데이트 가능)
    _controller.value =
        Matrix4.identity()
          ..translate(200, 200) // 초기 이동 변환 (중앙 정렬 시 필요)
          ..scale(_scale); // 초기 스케일 적용
  }

  @override
  Widget build(BuildContext context) {
    // 임의의 그래프 데이터 생성: 노드(vertexes)와 에지(edges)로 구성
    var vertexes = <Map>[]; // 노드 목록
    var r = Random(); // 랜덤 객체 생성
    for (var i = 0; i < 20; i++) {
      vertexes.add({
        'id': 'node$i', // 노드 고유 ID
        'tag': 'tag${r.nextInt(9)}', // 임의의 태그
        'tags': [
          // 여러 개의 태그 목록
          'tag${r.nextInt(9)}',
          if (r.nextBool()) 'tag${r.nextInt(4)}', // 랜덤하게 태그 추가
          if (r.nextBool()) 'tag${r.nextInt(8)}', // 랜덤하게 태그 추가
        ],
      });
    }
    var edges = <Map>[]; // 에지 목록
    for (var i = 0; i < 20; i++) {
      edges.add({
        'srcId': 'node${(i % 8) + 8}', // 시작 노드 ID
        'dstId': 'node$i', // 대상 노드 ID
        'edgeName': 'edge${r.nextInt(3)}', // 에지 이름
        'ranking': DateTime.now().millisecond, // 임의의 순위 값
      });
    }
    var data = {'vertexes': vertexes, 'edges': edges}; // 그래프 데이터 맵

    return LeftSidebarLayout(
      // 좌측 사이드바 레이아웃 사용
      activePage: PageType.graph, // 현재 활성화된 페이지 타입을 그래프로 설정
      child: Column(
        // 메인 콘텐츠 영역 구성
        children: [
          _buildTopBar(), // 상단 바 위젯 빌드
          // 알고리즘 선택 드롭다운 및 스케일 조절 슬라이더 UI
          Padding(
            padding: const EdgeInsets.all(8.0), // 내부 여백
            child: Row(
              // 자식 위젯을 가로로 배치
              mainAxisAlignment:
                  MainAxisAlignment.spaceAround, // 자식 위젯 주위에 균등한 공간 배분
              children: [
                // 그래프 레이아웃 알고리즘 선택 드롭다운
                DropdownButton<GraphAlgorithmType>(
                  value: _currentAlgorithmType, // 현재 선택된 값
                  items: <DropdownMenuItem<GraphAlgorithmType>>[
                    // 드롭다운 메뉴 아이템 목록
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
                    // 값 변경 시 호출
                    if (newValue != null) {
                      setState(() {
                        _currentAlgorithmType = newValue; // 상태 변경 및 위젯 다시 빌드 요청
                      });
                    }
                  },
                ),
                // 그래프 스케일 조절 슬라이더
                SizedBox(
                  width: 200, // 슬라이더 너비 설정
                  child: Slider(
                    value: _scale, // 현재 스케일 값
                    min: 0.1, // 최소 스케일
                    max: 2.0, // 최대 스케일
                    divisions: 20, // 분할 개수
                    label: _scale.toStringAsFixed(1), // 슬라이더 위에 표시될 레이블
                    onChanged: (double value) {
                      // 값 변경 시 호출
                      setState(() {
                        _scale = value; // 스케일 값 업데이트
                        // 슬라이더 값 변경 시 transformationController 업데이트하여 스케일 적용
                        _controller.value =
                            Matrix4.identity()
                              ..translate(200, 200) // 초기 이동 변환 유지
                              ..scale(_scale); // 새 스케일 적용
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildGraphArea(data)), // 남은 공간을 그래프 영역으로 채움
          // 하단에 Collapse 가능한 액션 영역 위젯 추가
          const CollapsibleBottomSection(),
        ],
      ),
    );
  }

  // 상단 바 위젯: 제목 표시
  Widget _buildTopBar() {
    return Container(
      height: 50,
      color: Colors.grey[300], // 배경색
      alignment: Alignment.centerRight, // 내용을 오른쪽으로 정렬
      padding: const EdgeInsets.symmetric(horizontal: 16), // 좌우 여백
      child: const Text(
        '2025 / 03', // 제목 텍스트
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  // FlutterGraphWidget을 반환하는 함수 (그래프 표시 영역)
  Widget _buildGraphArea(Map data) {
    return LayoutBuilder(
      // 부모 위젯의 크기 정보를 가져오기 위해 사용
      builder: (context, constraints) {
        // 사용 가능한 영역의 중앙 좌표 계산 후 초기 변환 설정
        Matrix4 initialTransform =
            Matrix4.identity()
              ..translate(
                constraints.maxWidth / 2,
                constraints.maxHeight / 2,
              ) // 중앙으로 이동
              ..scale(_scale); // 스케일 적용
        _controller.value =
            initialTransform; // TransformationController에 초기 변환 값 설정
        return InteractiveViewer(
          // 그래프를 확대/축소 및 이동 가능하게 하는 위젯
          transformationController: _controller, // 변환 관리를 위한 컨트롤러 연결
          boundaryMargin: const EdgeInsets.all(500), // 인터랙티브 영역의 경계 마진
          constrained:
              true, // true로 설정해 자식에 제약을 줌 (자식 크기가 InteractiveViewer보다 커지지 않도록 함)
          minScale: 0.1, // 최소 확대 배율
          maxScale: 5.0, // 최대 확대 배율
          child: SizedBox(
            // 자식 위젯의 크기를 InteractiveViewer 영역과 같게 설정
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: FlutterGraphWidget(
              // 실제 그래프를 그리는 위젯
              data: data, // 그래프 데이터
              algorithm: _getSelectedAlgorithm(), // 사용할 레이아웃 알고리즘
              convertor: MapConvertor(), // 데이터 변환기
              options:
                  Options() // 그래프 옵션 설정
                    ..enableHit =
                        false // 히트 감지 비활성화
                    ..panelDelay = const Duration(
                      milliseconds: 500,
                    ) // 패널 표시 지연 시간
                    ..graphStyle = // 그래프 스타일 설정
                        (GraphStyle()
                          ..tagColor = {
                            'tag8': Colors.orangeAccent.shade200,
                          } // 특정 태그 색상 설정
                          ..tagColorByIndex = [
                            // 인덱스별 태그 색상 목록
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
                    ..useLegend =
                        true // 범례 사용 여부
                    ..vertexPanelBuilder =
                        vertexPanelBuilder // 노드 패널 빌더 함수
                    ..edgeShape =
                        EdgeLineShape() // 에지 모양 (선)
                    ..vertexShape = VertexCircleShape(), // 노드 모양 (원)
            ),
          ),
        );
      },
    );
  }

  // 에지 패널 빌더: 에지 정보를 표시하는 위젯 (options 참조 대신 고정 값 사용)
  Widget edgePanelBuilder(Edge edge, Viewfinder viewfinder) {
    // 에지 위치를 로컬 좌표계에서 전역 좌표계로 변환
    var c = viewfinder.localToGlobal(edge.position);
    return Stack(
      // 여러 위젯을 겹쳐 표시
      children: [
        Positioned(
          // 절대 위치에 위젯 배치
          left: c.x + 5, // 에지 위치에서 오른쪽으로 5만큼 이동
          top: c.y, // 에지 위치의 Y 좌표
          child: SizedBox(
            // 위젯 크기 제한
            width: 200,
            child: ColoredBox(
              // 배경색이 있는 상자
              color: Colors.grey.shade900.withAlpha(200), // 반투명한 회색 배경
              child: ListTile(
                // 목록 형태의 위젯
                title: Text(
                  // 에지 이름 및 순위 표시
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

  // 버텍스 패널 빌더: 노드 정보를 표시하는 위젯
  Widget vertexPanelBuilder(dynamic hoverVertex, Viewfinder viewfinder) {
    // 노드 위치를 로컬 좌표계에서 전역 좌표계로 변환
    var c = viewfinder.localToGlobal(hoverVertex.cpn!.position);
    return Stack(
      // 여러 위젯을 겹쳐 표시
      children: [
        Positioned(
          // 절대 위치에 위젯 배치
          left:
              c.x +
              hoverVertex.radius +
              5, // 노드 위치에서 노드 반지름만큼 오른쪽으로 이동 후 5만큼 추가 이동
          top: c.y - 20, // 노드 위치에서 위쪽으로 20만큼 이동
          child: SizedBox(
            // 위젯 크기 제한
            width: 120,
            child: ColoredBox(
              // 배경색이 있는 상자
              color: Colors.grey.shade900.withAlpha(200), // 반투명한 회색 배경
              child: ListTile(
                // 목록 형태의 위젯
                title: Text(
                  'Id: ${hoverVertex.id}', // 노드 ID 표시
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  // 노드 태그 및 연결된 에지 수 표시
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
