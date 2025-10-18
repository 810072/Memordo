// lib/viewmodels/graph_customization_settings.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class GraphCustomizationSettings with ChangeNotifier {
  // 배경색
  Color _backgroundColor = const Color(0xFF1E1E1E);

  // 연결선 색상
  Color _linkColor = Colors.grey;
  double _linkOpacity = 0.4;
  double _linkWidth = 1.5;

  // 노드 아이콘 색상
  Color _nodeIconColor = Colors.white70;

  // 연결 개수에 따른 색상 (4단계)
  Color _isolatedNodeColor = const Color(0xFF616161); // 고립된 노트 (0개)
  Color _lowConnectionColor = const Color(0xFF757575); // 연결 1-2개
  Color _mediumConnectionColor = const Color(0xFF42A5F5); // 연결 3-5개
  Color _highConnectionColor = const Color(0xFFAB47BC); // 연결 6개 이상

  // Getters
  Color get backgroundColor => _backgroundColor;
  Color get linkColor => _linkColor;
  double get linkOpacity => _linkOpacity;
  double get linkWidth => _linkWidth;
  Color get nodeIconColor => _nodeIconColor;
  Color get isolatedNodeColor => _isolatedNodeColor;
  Color get lowConnectionColor => _lowConnectionColor;
  Color get mediumConnectionColor => _mediumConnectionColor;
  Color get highConnectionColor => _highConnectionColor;

  // Setters
  void setBackgroundColor(Color color) {
    _backgroundColor = color;
    notifyListeners();
    _saveSettings();
  }

  void setLinkColor(Color color) {
    _linkColor = color;
    notifyListeners();
    _saveSettings();
  }

  void setLinkOpacity(double opacity) {
    _linkOpacity = opacity;
    notifyListeners();
    _saveSettings();
  }

  void setLinkWidth(double width) {
    _linkWidth = width;
    notifyListeners();
    _saveSettings();
  }

  void setNodeIconColor(Color color) {
    _nodeIconColor = color;
    notifyListeners();
    _saveSettings();
  }

  void setIsolatedNodeColor(Color color) {
    _isolatedNodeColor = color;
    notifyListeners();
    _saveSettings();
  }

  void setLowConnectionColor(Color color) {
    _lowConnectionColor = color;
    notifyListeners();
    _saveSettings();
  }

  void setMediumConnectionColor(Color color) {
    _mediumConnectionColor = color;
    notifyListeners();
    _saveSettings();
  }

  void setHighConnectionColor(Color color) {
    _highConnectionColor = color;
    notifyListeners();
    _saveSettings();
  }

  // 연결 개수에 따른 색상 반환
  Color getNodeColorByLinks(int linkCount, bool isDarkMode) {
    if (linkCount == 0) return _isolatedNodeColor;
    if (linkCount < 3) return _lowConnectionColor;
    if (linkCount < 6) return _mediumConnectionColor;
    return _highConnectionColor;
  }

  // 기본값으로 리셋
  void resetToDefaults(bool isDarkMode) {
    _backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    _linkColor = Colors.grey;
    _linkOpacity = 0.4;
    _linkWidth = 1.5;
    _nodeIconColor = isDarkMode ? Colors.white70 : Colors.black87;

    if (isDarkMode) {
      _isolatedNodeColor = const Color(0xFF616161);
      _lowConnectionColor = const Color(0xFF757575);
      _mediumConnectionColor = const Color(0xFF1976D2);
      _highConnectionColor = const Color(0xFF7B1FA2);
    } else {
      _isolatedNodeColor = const Color(0xFFBDBDBD);
      _lowConnectionColor = const Color(0xFF9E9E9E);
      _mediumConnectionColor = const Color(0xFF42A5F5);
      _highConnectionColor = const Color(0xFFAB47BC);
    }

    notifyListeners();
    _saveSettings();
  }

  // 설정 저장
  Future<void> _saveSettings() async {
    try {
      final settings = {
        'backgroundColor': _backgroundColor.value,
        'linkColor': _linkColor.value,
        'linkOpacity': _linkOpacity,
        'linkWidth': _linkWidth,
        'nodeIconColor': _nodeIconColor.value,
        'isolatedNodeColor': _isolatedNodeColor.value,
        'lowConnectionColor': _lowConnectionColor.value,
        'mediumConnectionColor': _mediumConnectionColor.value,
        'highConnectionColor': _highConnectionColor.value,
      };

      final notesDir = await _getNotesDirectory();
      final settingsFile = File(p.join(notesDir, 'graph_customization.json'));
      await settingsFile.writeAsString(jsonEncode(settings));
      debugPrint('Graph customization settings saved.');
    } catch (e) {
      debugPrint('Failed to save graph customization settings: $e');
    }
  }

  // 설정 불러오기
  Future<void> loadSettings() async {
    try {
      final notesDir = await _getNotesDirectory();
      final settingsFile = File(p.join(notesDir, 'graph_customization.json'));

      if (await settingsFile.exists()) {
        final content = await settingsFile.readAsString();
        final settings = jsonDecode(content) as Map<String, dynamic>;

        _backgroundColor = Color(settings['backgroundColor'] as int);
        _linkColor = Color(settings['linkColor'] as int);
        _linkOpacity = (settings['linkOpacity'] as num).toDouble();
        _linkWidth = (settings['linkWidth'] as num).toDouble();
        _nodeIconColor = Color(settings['nodeIconColor'] as int);
        _isolatedNodeColor = Color(settings['isolatedNodeColor'] as int);
        _lowConnectionColor = Color(settings['lowConnectionColor'] as int);
        _mediumConnectionColor = Color(
          settings['mediumConnectionColor'] as int,
        );
        _highConnectionColor = Color(settings['highConnectionColor'] as int);

        notifyListeners();
        debugPrint('Graph customization settings loaded.');
      }
    } catch (e) {
      debugPrint('Failed to load graph customization settings: $e');
    }
  }

  Future<String> _getNotesDirectory() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) throw Exception('홈 디렉터리를 찾을 수 없습니다.');
    return Platform.isMacOS
        ? p.join(home, 'Memordo_Notes')
        : p.join(home, 'Documents', 'Memordo_Notes');
  }
}
