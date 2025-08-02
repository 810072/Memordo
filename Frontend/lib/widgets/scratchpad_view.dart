// lib/widgets/scratchpad_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/scratchpad_provider.dart';

class ScratchpadView extends StatelessWidget {
  const ScratchpadView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Provider를 통해 컨트롤러에 접근합니다.
    final scratchpadProvider = context.watch<ScratchpadProvider>();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: TextField(
        controller: scratchpadProvider.controller,
        maxLines: null, // 여러 줄 입력 가능
        expands: true, // 사용 가능한 공간을 모두 채움
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration.collapsed(
          hintText: '임시 아이디어나 링크를 여기에 붙여넣으세요...',
          hintStyle: TextStyle(color: Colors.grey),
        ),
        style: const TextStyle(fontSize: 13, height: 1.5),
      ),
    );
  }
}
