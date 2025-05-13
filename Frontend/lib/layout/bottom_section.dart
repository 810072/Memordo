import 'package:flutter/material.dart';

/// 하단에서 마우스로 높이 조절 가능한 액션 영역 위젯
class CollapsibleBottomSection extends StatefulWidget {
  final VoidCallback? onSummarizePressed; // "내용 요약" 버튼 콜백 함수

  const CollapsibleBottomSection({super.key, this.onSummarizePressed});

  @override
  State<CollapsibleBottomSection> createState() =>
      _CollapsibleBottomSectionState();
}

class _CollapsibleBottomSectionState extends State<CollapsibleBottomSection> {
  double _height = 220; // 현재 바텀 섹션 높이
  final double _minHeight = 60; // 최소 높이
  double _maxHeight = 400; // 최대 높이 (context 반영하여 초기화 예정)
  double _startDy = 0; // 드래그 시작 시 Y 좌표
  double _startHeight = 0; // 드래그 시작 시 높이

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    _maxHeight =
        screenHeight - kToolbarHeight - bottomPadding - 50; // 남은 여유 공간 계산

    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown, // 마우스 커서를 상하조절 아이콘으로 변경
      child: GestureDetector(
        // 드래그 시작 시 초기값 저장
        onVerticalDragStart: (details) {
          _startDy = details.globalPosition.dy;
          _startHeight = _height;
        },
        // 드래그 중 높이 조절 (빠릿하게 반응하도록 즉시 적용)
        onVerticalDragUpdate: (details) {
          final drag = details.globalPosition.dy - _startDy;
          final newHeight = (_startHeight - drag).clamp(_minHeight, _maxHeight);
          setState(() {
            _height = newHeight;
          });
        },
        child: Container(
          height: _height,
          constraints: BoxConstraints(maxHeight: _maxHeight),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade400)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 드래그 핸들
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              // 내용 영역
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 버튼 행
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: widget.onSummarizePressed, // 내용 요약
                            child: const Text('내용 요약'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {}, // TODO: 태그 추출 기능 연결 예정
                            child: const Text('태그 추출'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {}, // TODO: 검색 기능 연결 예정
                            child: const Text('검색'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // 요약 결과 제목 (나중에 실제 결과 표시 가능)
                      const Text(
                        'AI 요약 내용...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // 적용 버튼
                      Align(
                        alignment: Alignment.bottomRight,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(120, 40),
                          ),
                          onPressed: () {}, // TODO: 요약 내용 적용 로직 연결 예정
                          child: const Text('적용'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
