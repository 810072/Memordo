// lib/widgets/note_outline_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/note_provider.dart';

class NoteOutlineView extends StatelessWidget {
  const NoteOutlineView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Consumer를 사용하여 NoteProvider의 변경 사항을 감지합니다.
    return Consumer<NoteProvider>(
      builder: (context, noteProvider, child) {
        // 컨트롤러가 아직 등록되지 않았으면 안내 메시지를 표시합니다.
        if (noteProvider.controller == null) {
          return const Center(
            child: Text(
              '메모를 열면 개요가 표시됩니다.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final headers = noteProvider.parseHeaders();

        // 헤더가 없으면 안내 메시지를 표시합니다.
        if (headers.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "메모에 '#'을 사용하여 제목을 추가하면 여기에 목차가 나타납니다.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        // 헤더 목록을 ListView로 표시합니다.
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          itemCount: headers.length,
          itemBuilder: (context, index) {
            final header = headers[index];
            return InkWell(
              onTap: () {
                // 헤더를 탭하면 해당 위치로 이동합니다.
                noteProvider.jumpTo(header.position);
              },
              borderRadius: BorderRadius.circular(4.0),
              child: Padding(
                // 헤더 레벨에 따라 들여쓰기를 적용합니다.
                padding: EdgeInsets.only(
                  left: (header.level - 1) * 12.0,
                  top: 6.0,
                  bottom: 6.0,
                  right: 4.0,
                ),
                child: Text(
                  header.text,
                  style: TextStyle(
                    fontSize: 13,
                    // 헤더 레벨에 따라 폰트 두께를 다르게 설정합니다.
                    fontWeight:
                        header.level == 1 ? FontWeight.bold : FontWeight.normal,
                    color: Colors.grey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
