// lib/providers/scratchpad_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScratchpadProvider with ChangeNotifier {
  static const _saveKey = 'scratchpad_text';
  late final TextEditingController controller;
  Timer? _debounce;

  ScratchpadProvider() {
    controller = TextEditingController();
    _loadText();
    // 텍스트가 변경될 때마다 500ms 지연 후 자동 저장합니다.
    controller.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        _saveText();
      });
    });
  }

  // SharedPreferences에서 텍스트를 불러옵니다.
  Future<void> _loadText() async {
    final prefs = await SharedPreferences.getInstance();
    final savedText = prefs.getString(_saveKey) ?? '';
    controller.text = savedText;
  }

  // 현재 텍스트를 SharedPreferences에 저장합니다.
  Future<void> _saveText() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveKey, controller.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    super.dispose();
  }
}
