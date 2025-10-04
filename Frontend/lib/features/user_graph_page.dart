// lib/features/user_graph_page.dart
import 'package:flutter/material.dart';

class UserGraphPage extends StatelessWidget {
  const UserGraphPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('사용자 정의 그래프')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.share_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              '사용자 정의 그래프 뷰',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 10),
            Text(
              '이곳에 <<링크>>로 연결된 노트 관계도가 표시될 예정입니다.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
