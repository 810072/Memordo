// lib/model/note_model.dart
import 'package:flutter/material.dart';

class NoteTab {
  String id;
  String title;
  TextEditingController controller;
  FocusNode focusNode;
  String? filePath;
  bool isEdited;
  // ✨ [추가] 각 탭이 자신의 리스너 함수를 가지도록 수정
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
