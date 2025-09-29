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
        if (controller.isLoading) {
          return const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2.5),
                SizedBox(width: 16),
                Flexible(child: Text("AI가 요약 중입니다...")),
              ],
            ),
          );
        }

        final textStyle = TextStyle(
          fontSize: 13,
          color:
              controller.summaryText.isEmpty
                  ? Colors.grey.shade600
                  : Colors.grey.shade800,
          height: 1.6,
        );

        final String summaryText =
            controller.summaryText.isEmpty
                ? '내용 요약 AI'
                : controller.summaryText;

        // ✨ [수정] RichText와 TextSpan을 사용하여 아이콘과 텍스트를 유연하게 배치
        return SingleChildScrollView(
          child: RichText(
            text: TextSpan(
              children: [
                // 아이콘을 텍스트의 일부처럼 처리
                WidgetSpan(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: Icon(
                      Icons.auto_awesome,
                      color: Colors.deepPurple.shade300,
                      size: 20,
                    ),
                  ),
                  alignment: PlaceholderAlignment.top, // 아이콘을 텍스트 상단에 정렬
                ),
                // 실제 요약 텍스트
                TextSpan(text: summaryText, style: textStyle),
              ],
            ),
          ),
        );
      },
    );
  }
}
