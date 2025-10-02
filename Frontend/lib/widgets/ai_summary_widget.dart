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

        final String summaryText = hasSummary ? controller.summaryText : '';

        return Stack(
          children: [
            SingleChildScrollView(
              // ✨ [수정] Row를 사용하여 아이콘과 텍스트를 분리하고 전체 너비를 차지하도록 함
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 아이콘 (선택/복사 불가)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0, top: 3.0),
                    child: Icon(
                      Icons.auto_awesome,
                      color: Colors.deepPurple.shade300,
                      size: 20,
                    ),
                  ),
                  // 텍스트 (선택/복사 가능)
                  Expanded(
                    child: SelectableText(summaryText, style: textStyle),
                  ),
                ],
              ),
            ),
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
