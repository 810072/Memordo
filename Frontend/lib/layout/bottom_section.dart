import 'package:flutter/material.dart';

/// 하단에서 요약 결과를 표시하고 조절할 수 있는 섹션
class CollapsibleBottomSection extends StatefulWidget {
  final VoidCallback? onSummarizePressed; // 요약 버튼 콜백
  final bool isLoading; // << 1. isLoading 멤버 변수 추가

  const CollapsibleBottomSection({
    super.key,
    this.onSummarizePressed,
    this.isLoading = false, // << 2. 생성자에 isLoading 파라미터 추가 (기본값 false)
  });

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

  String _summaryText = ''; // AI 요약 결과를 저장하는 상태 변수

  /// 외부에서 요약 결과를 전달받아 업데이트
  void updateSummary(String summary) {
    if (mounted) {
      setState(() {
        _summaryText = summary;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 화면 크기에 따라 maxHeight 재계산 (initState 이후에도 호출될 수 있도록)
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    // kToolbarHeight는 AppBar 높이, bottomPadding은 하단 시스템 UI 영역
    // 150은 대략적인 상단 영역과 추가 여백을 고려한 값, 조절 필요
    _maxHeight = screenHeight - kToolbarHeight - bottomPadding - 150;
    if (_height > _maxHeight) {
      _height = _maxHeight; // 현재 높이가 최대 높이를 넘지 않도록 조정
    }
  }

  @override
  Widget build(BuildContext context) {
    // didChangeDependencies에서 maxHeight가 설정되므로 build에서 매번 호출할 필요 없음
    // final screenHeight = MediaQuery.of(context).size.height;
    // final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    // _maxHeight = screenHeight - kToolbarHeight - bottomPadding - 150;

    return Container(
      // 높이 값 범위 제한
      height: _height.clamp(_minHeight, _maxHeight),
      constraints: BoxConstraints(maxHeight: _maxHeight), // 최대 높이 제한
      decoration: BoxDecoration(
        color: Colors.white, // 배경색
        border: Border(top: BorderSide(color: Colors.grey.shade300)), // 상단 경계선
        boxShadow: const [
          // 그림자 효과
          BoxShadow(
            color: Colors.black12,
            blurRadius: 5,
            offset: Offset(0, -2), // 위쪽으로 그림자
          ),
        ],
      ),
      child: Column(
        children: [
          // 드래그 핸들
          GestureDetector(
            onVerticalDragStart: (details) {
              _startDy = details.globalPosition.dy;
              _startHeight = _height;
            },
            onVerticalDragUpdate: (details) {
              final dragDistance = details.globalPosition.dy - _startDy;
              // 위로 드래그하면 높이 증가, 아래로 드래그하면 높이 감소
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
                height: 6, // 핸들 두께
                margin: const EdgeInsets.only(top: 8, bottom: 10), // 핸들 상하 여백
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          // 내용 영역 (Expanded와 SingleChildScrollView로 스크롤 가능하게)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
              ).copyWith(bottom: 16.0), // 내부 패딩
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 버튼 영역
                  Row(
                    children: [
                      // << 3. isLoading 상태에 따라 버튼 UI 변경 >>
                      ElevatedButton.icon(
                        icon:
                            widget.isLoading
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
                        label: Text(widget.isLoading ? '요약 중...' : '내용 요약'),
                        onPressed:
                            widget.isLoading
                                ? null
                                : widget.onSummarizePressed, // 로딩 중이면 비활성화
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
                          // TODO: 태그 추출 기능 연결 예정
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('태그 추출 기능은 준비 중입니다.')),
                          );
                        },
                        child: const Text('태그 추출'),
                      ),
                      // const SizedBox(width: 10), // 검색 버튼은 필요시 추가
                      // ElevatedButton(
                      //   onPressed: () {},
                      //   child: const Text('검색'),
                      // ),
                    ],
                  ),
                  const SizedBox(height: 16), // 버튼과 요약 내용 사이 간격
                  Text(
                    'AI 요약 내용', // 섹션 제목
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity, // 너비 최대로
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(4.0),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    constraints: const BoxConstraints(
                      minHeight: 80,
                    ), // 요약 내용 최소 높이
                    child: SelectableText(
                      _summaryText.isEmpty && !widget.isLoading
                          ? '요약할 항목을 히스토리에서 선택 후 "내용 요약" 버튼을 누르세요.'
                          : widget.isLoading &&
                              _summaryText.contains("요약 중...") // 초기 요약 중 메시지 유지
                          ? _summaryText // "URL 요약 중..." 메시지 표시
                          : _summaryText,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[850],
                        height: 1.5,
                      ),
                    ),
                  ),
                  // "적용" 버튼은 현재 기능이 명확하지 않아 일단 주석 처리 또는 제거
                  // const SizedBox(height: 20),
                  // Align(
                  //   alignment: Alignment.bottomRight,
                  //   child: ElevatedButton(
                  //     onPressed: () {}, // TODO: 요약 적용 기능
                  //     child: const Text('적용'),
                  //   ),
                  // ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
