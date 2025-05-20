// lib/layout/bottom_section.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 임포트
import 'bottom_section_controller.dart'; // 컨트롤러 임포트

/// 하단에서 요약 결과를 표시하고 조절할 수 있는 섹션
class CollapsibleBottomSection extends StatefulWidget {
  // onSummarizePressed는 여전히 필요 (특정 페이지에서만 요약 기능 제공)
  final VoidCallback? onSummarizePressed;

  const CollapsibleBottomSection({super.key, this.onSummarizePressed});

  @override
  CollapsibleBottomSectionState createState() =>
      CollapsibleBottomSectionState();
}

/// 상태 클래스 - 외부에서 접근해야 하므로 public으로 선언
class CollapsibleBottomSectionState extends State<CollapsibleBottomSection> {
  double _height = 120; // 초기 높이
  final double _minHeight = 60; // 최소 높이 (드래그 핸들 + 버튼 영역 고려)
  double _maxHeight = 400; // 최대 높이 (실행 중 계산됨)
  double _startDy = 0; // 드래그 시작 위치
  double _startHeight = 0; // 드래그 시작 시 높이

  // _summaryText, _isLoading은 이제 BottomSectionController에서 관리됩니다.
  // void updateSummary(String summary) { /* 제거 */ }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    _maxHeight = screenHeight - kToolbarHeight - bottomPadding - 150;
    if (_height > _maxHeight) {
      _height = _maxHeight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BottomSectionController>(
      // BottomSectionController를 구독
      builder: (context, controller, child) {
        if (!controller.isVisible) {
          // isVisible 상태에 따라 하단 영역 숨기기
          return const SizedBox.shrink(); // 숨겨진 상태에서는 아무것도 렌더링하지 않음
        }

        return Container(
          height: _height.clamp(_minHeight, _maxHeight),
          constraints: BoxConstraints(maxHeight: _maxHeight),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 5,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              GestureDetector(
                onVerticalDragStart: (details) {
                  _startDy = details.globalPosition.dy;
                  _startHeight = _height;
                },
                onVerticalDragUpdate: (details) {
                  final dragDistance = details.globalPosition.dy - _startDy;
                  final newHeight = (_startHeight - dragDistance).clamp(
                    _minHeight,
                    _maxHeight,
                  );
                  if (mounted) {
                    setState(() {
                      _height = newHeight;
                    });
                  }
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: Container(
                    width: 40,
                    height: 6,
                    margin: const EdgeInsets.only(top: 8, bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                  ).copyWith(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon:
                                controller
                                        .isLoading // 컨트롤러의 isLoading 사용
                                    ? Container(
                                      width: 18,
                                      height: 18,
                                      child: const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                    : const Icon(
                                      Icons.summarize_outlined,
                                      size: 20,
                                    ),
                            label: Text(
                              controller.isLoading ? '요약 중...' : '내용 요약',
                            ), // 컨트롤러의 isLoading 사용
                            onPressed:
                                controller
                                        .isLoading // 컨트롤러의 isLoading 사용
                                    ? null
                                    : widget.onSummarizePressed,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('태그 추출 기능은 준비 중입니다.'),
                                ),
                              );
                            },
                            child: const Text('태그 추출'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'AI 요약 내용',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(4.0),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        constraints: const BoxConstraints(minHeight: 80),
                        child: SelectableText(
                          controller
                                  .isLoading // 컨트롤러의 isLoading 사용
                              ? '요약 중...' // 로딩 중일 때는 로딩 메시지
                              : controller
                                  .summaryText
                                  .isEmpty // 로딩 중이 아니면서 텍스트가 비어있을 때
                              ? '요약할 항목을 히스토리에서 선택 후 "내용 요약" 버튼을 누르세요.'
                              : controller.summaryText, // 실제 요약 내용
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[850],
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
