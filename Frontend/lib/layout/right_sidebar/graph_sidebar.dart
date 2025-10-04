// lib/layout/right_sidebar/graph_sidebar.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/graph_viewmodel.dart';

class GraphSidebar extends StatelessWidget {
  const GraphSidebar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ✨ [수정] ViewModel을 watch하여 현재 뷰 상태를 실시간으로 반영
    final graphViewModel = context.watch<GraphViewModel>();

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
              "그래프 뷰 전환",
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
                // AI 그래프 보기 버튼
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('AI 추천 관계'),
                  style: ElevatedButton.styleFrom(
                    // 현재 활성화된 뷰에 따라 버튼 스타일 변경
                    backgroundColor:
                        graphViewModel.isAiGraphView
                            ? theme.primaryColor
                            : theme.disabledColor,
                  ),
                  onPressed: () {
                    // AI 그래프 뷰로 전환
                    graphViewModel.setGraphView(true);
                  },
                ),
                const SizedBox(height: 12),
                // 사용자 그래프 보기 버튼
                ElevatedButton.icon(
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('사용자 정의 링크'),
                  style: ElevatedButton.styleFrom(
                    // 현재 활성화된 뷰에 따라 버튼 스타일 변경
                    backgroundColor:
                        !graphViewModel.isAiGraphView
                            ? theme.primaryColor
                            : theme.disabledColor,
                  ),
                  onPressed: () {
                    // ✨ [핵심 수정] 버튼을 눌렀을 때 사용자 그래프를 생성하는 함수 호출
                    context.read<GraphViewModel>().buildUserGraph();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
