// bottom_section.dart
import 'package:flutter/material.dart';

// 접을 수 있는 하단 액션 영역 위젯
class CollapsibleBottomSection extends StatefulWidget {
  const CollapsibleBottomSection({super.key});

  @override
  State<CollapsibleBottomSection> createState() =>
      _CollapsibleBottomSectionState();
}

// CollapsibleBottomSection 위젯의 상태를 관리하는 클래스
class _CollapsibleBottomSectionState extends State<CollapsibleBottomSection> {
  // 하단 영역이 확장되었는지 여부를 나타내는 상태 변수
  bool _isExpanded = true;

  // 하단 영역의 확장/축소 상태를 토글하는 함수
  void _toggleSection() {
    setState(() {
      _isExpanded = !_isExpanded; // 상태 변경 및 위젯 다시 빌드 요청
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // 상단에 테두리선 추가
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade400)),
      ),
      padding: const EdgeInsets.all(16), // 내부 여백
      child: Column(
        mainAxisSize: MainAxisSize.min, // 컬럼 크기를 자식 위젯에 맞춤
        crossAxisAlignment: CrossAxisAlignment.start, // 자식 위젯을 왼쪽으로 정렬
        children: [
          // 헤더: 제목과 토글 아이콘을 포함하는 영역
          GestureDetector(
            onTap: _toggleSection, // 탭하면 _toggleSection 함수 호출
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween, // 자식 위젯을 양 끝으로 정렬
              children: [
                // 헤더 제목
                const Text(
                  '하단 액션 영역',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                // 확장/축소 상태에 따라 아이콘 변경
                Icon(
                  _isExpanded
                      ? Icons
                          .keyboard_arrow_up // 확장 시 위쪽 화살표
                      : Icons.keyboard_arrow_down, // 축소 시 아래쪽 화살표
                ),
              ],
            ),
          ),
          // 내용 영역: AnimatedCrossFade로 부드럽게 숨김/보임 전환
          AnimatedCrossFade(
            // 확장 시 보여줄 위젯 (내용)
            firstChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // 자식 위젯을 왼쪽으로 정렬
              children: [
                const SizedBox(height: 10),
                // 스크롤 가능한 버튼 행
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal, // 가로 스크롤
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: () {}, // 버튼 클릭 시 실행될 함수 (현재는 비어있음)
                        child: const Text('내용 요약'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () {}, // 버튼 클릭 시 실행될 함수 (현재는 비어있음)
                        child: const Text('태그 추출'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () {},
                        child: const Text('검색'),
                      ), // 버튼 클릭 시 실행될 함수 (현재는 비어있음)
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // AI 요약 내용 제목
                const Text(
                  'AI 요약 내용...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                // '적용' 버튼을 오른쪽 하단에 정렬
                Align(
                  alignment: Alignment.bottomRight,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(120, 40), // 버튼 최소 크기 설정
                    ),
                    onPressed: () {}, // 버튼 클릭 시 실행될 함수 (현재는 비어있음)
                    child: const Text('적용'),
                  ),
                ),
              ],
            ),
            // 축소 시 보여줄 위젯 (빈 컨테이너), 명시적으로 높이를 0으로 설정하여 레이아웃 안정화 시도
            secondChild: Container(height: 0.0), // <-- 이 부분 추가 또는 수정
            // 현재 상태에 따라 보여줄 위젯 결정
            crossFadeState:
                _isExpanded
                    ? CrossFadeState
                        .showFirst // 확장 시 firstChild 표시
                    : CrossFadeState.showSecond, // 축소 시 secondChild 표시
            duration: const Duration(milliseconds: 300), // 전환 애니메이션 시간
            // Optional: 애니메이션 커브를 지정하여 부드러움 조절 가능
            // firstCurve: Curves.easeIn,
            // secondCurve: Curves.easeOut,
            // sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }
}
