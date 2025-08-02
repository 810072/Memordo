// lib/widgets/ai_summary_widget.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layout/bottom_section_controller.dart';

class AiSummaryWidget extends StatelessWidget {
  const AiSummaryWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<BottomSectionController>(
      builder: (context, controller, child) {
        // 로딩 중일 때 UI
        if (controller.isLoading) {
          return const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2.5),
                SizedBox(width: 16),
                Text("AI가 요약 중입니다..."),
              ],
            ),
          );
        }

        // ✨ [수정] 챗봇 스타일로 디자인을 변경합니다.
        return SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI 아이콘
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Icon(
                  Icons.auto_awesome, // Gemini를 상징하는 아이콘
                  color: Colors.deepPurple.shade300,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // 요약 텍스트
              Expanded(
                child: SelectableText(
                  controller.summaryText.isEmpty
                      ? '내용 요약 AI' // 더 자연스러운 안내 문구
                      : controller.summaryText,
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        controller.summaryText.isEmpty
                            ? Colors.grey.shade600
                            : Colors.grey.shade800,
                    height: 1.6, // 줄 간격을 조절하여 가독성 향상
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
