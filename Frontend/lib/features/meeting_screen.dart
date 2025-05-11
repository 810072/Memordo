import 'dart:io' show File, Directory, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../layout/bottom_section.dart';
import '../utils/web_helper.dart';

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final TextEditingController _controller = TextEditingController();
  String _status = '';

  /// ✅ 원하는 저장 경로 설정
  Future<String> getCustomSavePath() async {
    final home = Platform.environment['HOME'] ?? '/Users/unknown_user';
    final folderPath = '$home/Memo'; // 완전히 명시적인 경로 사용
    final directory = Directory(folderPath);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return folderPath;
  }

  Future<void> _saveMarkdown() async {
    final content = _controller.text;

    if (kIsWeb) {
      downloadMarkdownWeb(content);
      setState(() {
        _status = "웹에서 다운로드됨 ✅";
      });
    } else if (Platform.isMacOS) {
      try {
        final saveDir = await getCustomSavePath();
        final fileName = 'note_${DateTime.now().millisecondsSinceEpoch}.md';
        final filePath = p.join(saveDir, fileName);

        final file = File(filePath);
        await file.writeAsString(content);
        setState(() {
          _status = "저장 완료: $filePath";
        });
      } catch (e) {
        setState(() {
          _status = "오류 발생 ❌: $e";
        });
      }
    } else {
      setState(() {
        _status = "이 플랫폼은 아직 지원되지 않아요 🛑";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 50,
          color: Colors.grey[300],
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const Text(
            '메인 화면',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                      hintText: '여기에 글을 작성하세요...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _saveMarkdown,
                      child: const Text('.md 파일로 저장'),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _status,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const CollapsibleBottomSection(),
      ],
    );
  }
}
