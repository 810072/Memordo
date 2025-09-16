// lib/model/note_model.dart

// 'package.flutter/material.dart' -> 'package:flutter/material.dart'로 수정
import 'package:flutter/material.dart';

class NoteTab {
  String id; // 고유 ID (파일 경로 또는 임시 ID)
  String title; // 탭에 표시될 제목
  TextEditingController controller; // 각 탭의 텍스트 편집을 위한 컨트롤러
  FocusNode focusNode; // 각 탭의 포커스를 위한 노드
  String? filePath; // 파일의 실제 경로
  bool isEdited; // 수정되었는지 여부

  NoteTab({
    required this.id,
    required this.title,
    required this.controller,
    required this.focusNode,
    this.filePath,
    this.isEdited = false,
  });
}
