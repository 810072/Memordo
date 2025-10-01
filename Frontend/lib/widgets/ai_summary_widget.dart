// lib/widgets/ai_summary_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard 사용을 위해 추가
import 'package:provider/provider.dart';
import '../layout/bottom_section_controller.dart';
import '../providers/status_bar_provider.dart'; // SnackBar 대신 상태바 사용을 위해 추가

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

        final bool hasSummary = controller.summaryText.isNotEmpty;
        final textStyle = TextStyle(
          fontSize: 13,
          color: hasSummary ? Colors.grey.shade800 : Colors.grey.shade600,
          height: 1.6,
        );

        final String summaryText =
            hasSummary ? controller.summaryText : '내용 요약 AI';

        // ✨ [수정] Stack을 사용하여 복사 버튼을 요약 텍스트 위에 배치합니다.
        return Stack(
          children: [
            // ✨ [수정] RichText 대신 SelectableText.rich를 사용하여 텍스트 선택 및 복사가 가능하도록 합니다.
            SingleChildScrollView(
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: Icon(
                          Icons.auto_awesome,
                          color: Colors.deepPurple.shade300,
                          size: 20,
                        ),
                      ),
                      alignment: PlaceholderAlignment.top,
                    ),
                    TextSpan(text: summaryText, style: textStyle),
                  ],
                ),
              ),
            ),
            // ✨ [추가] 요약 내용이 있을 때만 복사 버튼을 표시합니다.
            if (hasSummary)
              Positioned(
                bottom: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  tooltip: '요약 내용 복사',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: controller.summaryText),
                    );
                    // ✨ [수정] SnackBar 대신 StatusBarProvider를 사용하여 사용자에게 피드백을 줍니다.
                    context.read<StatusBarProvider>().showStatusMessage(
                      '요약 내용이 클립보드에 복사되었습니다.',
                      type: StatusType.success,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
