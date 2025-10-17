// lib/layout/right_sidebar/graph_sidebar.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/graph_viewmodel.dart';

class GraphSidebar extends StatelessWidget {
  const GraphSidebar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final graphViewModel = context.watch<GraphViewModel>();

    // 활성화된 버튼 스타일
    final ButtonStyle activeStyle = ElevatedButton.styleFrom(
      backgroundColor: theme.primaryColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
      padding: const EdgeInsets.symmetric(vertical: 8),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      elevation: 2,
    );

    // 비활성화된 버튼 스타일 (테두리 강조)
    final ButtonStyle inactiveStyle = OutlinedButton.styleFrom(
      backgroundColor: theme.cardColor,
      foregroundColor: theme.textTheme.bodyMedium?.color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
      side: BorderSide(
        color: theme.dividerColor.withOpacity(0.8), // 테두리 색을 더 진하게
        width: 1.5, // 테두리 두께 증가
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
    );

    return Column(
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "그래프 뷰 옵션",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // AI 추천 관계 버튼
                // ElevatedButton(
                //   child: const Text('AI 추천 관계'),
                //   style:
                //       graphViewModel.isAiGraphView
                //           ? activeStyle
                //           : inactiveStyle,
                //   onPressed: () {
                //     graphViewModel.setGraphView(true);
                //   },
                // ),
                // const SizedBox(height: 12),
                // // 사용자 정의 링크 버튼
                // ElevatedButton(
                //   child: const Text('사용자 정의 링크'),
                //   style:
                //       !graphViewModel.isAiGraphView
                //           ? activeStyle
                //           : inactiveStyle,
                //   onPressed: () {
                //     context.read<GraphViewModel>().buildUserGraph();
                //   },
                // ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
