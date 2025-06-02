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
        return Container(
          margin: const EdgeInsets.only(top: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Summary',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 150),
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC), // bg-slate-50
                  borderRadius: BorderRadius.circular(12.0), // rounded-xl
                  border: Border.all(
                    color: Colors.grey.shade300!,
                  ), // border-slate-300
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child:
                    controller.isLoading
                        ? Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(strokeWidth: 2.5),
                              SizedBox(width: 16),
                              Text("AI가 요약 중입니다..."),
                            ],
                          ),
                        )
                        : SelectableText(
                          controller.summaryText.isEmpty
                              ? 'AI-generated summary will appear here...'
                              : controller.summaryText,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            height: 1.5,
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
