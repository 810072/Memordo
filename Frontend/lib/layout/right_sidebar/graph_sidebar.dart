// lib/layout/right_sidebar/graph_sidebar.dart

import 'package:flutter/material.dart';

class GraphSidebar extends StatelessWidget {
  const GraphSidebar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              "그래프 정보",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const Expanded(
          child: Center(
            child: Text('그래프 정보 표시 영역', style: TextStyle(color: Colors.grey)),
          ),
        ),
      ],
    );
  }
}
