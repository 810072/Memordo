import 'package:flutter/material.dart';

/// 하단에서 요약 결과를 표시하고 조절할 수 있는 섹션
class CollapsibleBottomSection extends StatefulWidget {
  final VoidCallback? onSummarizePressed; // 요약 버튼 콜백

  const CollapsibleBottomSection({super.key, this.onSummarizePressed});

  @override
  CollapsibleBottomSectionState createState() =>
      CollapsibleBottomSectionState();
}

/// 상태 클래스 - 외부에서 접근해야 하므로 public으로 선언
class CollapsibleBottomSectionState extends State<CollapsibleBottomSection> {
  double _height = 220; // 초기 높이
  final double _minHeight = 60; // 최소 높이
  double _maxHeight = 400; // 최대 높이 (실행 중 계산됨)
  double _startDy = 0; // 드래그 시작 위치
  double _startHeight = 0; // 드래그 시작 시 높이

  String _summaryText = ''; // AI 요약 결과를 저장하는 상태 변수

  /// 외부에서 요약 결과를 전달받아 업데이트
  void updateSummary(String summary) {
    setState(() {
      _summaryText = summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    _maxHeight = screenHeight - kToolbarHeight - bottomPadding - 50;

    return Container(
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
          // ✅ 드래그 핸들에만 GestureDetector 적용하여 드래그 영역 제한
          GestureDetector(
            onVerticalDragStart: (details) {
              _startDy = details.globalPosition.dy;
              _startHeight = _height;
            },
            onVerticalDragUpdate: (details) {
              final drag = details.globalPosition.dy - _startDy;
              final newHeight = (_startHeight - drag).clamp(
                _minHeight,
                _maxHeight,
              );
              setState(() {
                _height = newHeight;
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
          ),
          // 하단 요약 내용 및 버튼 UI
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 버튼 영역
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: widget.onSummarizePressed,
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
                  const Text(
                    'AI 요약 내용...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  if (_summaryText.isNotEmpty)
                    Text(_summaryText, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: ElevatedButton(
                      onPressed: () {}, // TODO: 요약 적용 기능
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
