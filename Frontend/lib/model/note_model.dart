// lib/model/note_model.dart

import 'package:flutter/material.dart';

class NoteTab {
  String id;
  String title;
  TextEditingController controller; // ✨ [수정] 타입을 TextEditingController로 변경
  FocusNode focusNode;
  String? filePath;
  bool isEdited;
  VoidCallback? contentListener;

  NoteTab({
    required this.id,
    required this.title,
    required this.controller,
    required this.focusNode,
    this.filePath,
    this.isEdited = false,
  });
}
