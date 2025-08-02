// Frontend/lib/providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { light, dark }

class ThemeProvider with ChangeNotifier {
  AppThemeMode _themeMode = AppThemeMode.light; // 기본값: 라이트 모드
  static const String _themeModeKey = 'app_theme_mode';

  ThemeProvider() {
    _loadThemeMode();
  }

  AppThemeMode get themeMode => _themeMode;

  ThemeData get currentThemeData {
    // 앱의 현재 테마 모드에 따라 LightTheme 또는 DarkTheme를 반환합니다.
    return _themeMode == AppThemeMode.dark ? _darkTheme : _lightTheme;
  }

  void setThemeMode(AppThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      _saveThemeMode(mode);
      notifyListeners();
    }
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMode = prefs.getString(_themeModeKey);
    if (storedMode == 'dark') {
      _themeMode = AppThemeMode.dark;
    } else {
      _themeMode = AppThemeMode.light;
    }
    notifyListeners();
  }

  Future<void> _saveThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.toString().split('.').last);
  }

  // 라이트 테마 정의
  final ThemeData _lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: const Color(0xFF3d98f4), // 앱의 주요 색상
    scaffoldBackgroundColor: Colors.white, // 메모 영역은 흰색으로 유지
    // ✨ [수정] 앱바 배경색을 흰색으로 변경
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1E293B), // 앱바 전경색 (아이콘, 텍스트)
      elevation: 1.0,
      shadowColor: Colors.black12,
    ),
    // 사이드바 배경색은 이전의 연한 회색으로 유지
    cardColor: const Color(0xFFF8F9FA),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: Colors.grey.shade800),
      titleMedium: TextStyle(color: Colors.grey.shade700),
      bodyLarge: TextStyle(color: Colors.grey.shade800),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.black54,
      textColor: Colors.black87,
    ),
  );

  // 다크 테마 정의
  final ThemeData _darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.deepPurple.shade300,
    scaffoldBackgroundColor: const Color(0xFF12182B),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF1E273B),
      foregroundColor: Colors.white,
      elevation: 1.0,
    ),
    cardColor: const Color(0xFF1E273B),
    textTheme: TextTheme(
      bodyMedium: const TextStyle(color: Colors.white),
      titleMedium: const TextStyle(color: Colors.white),
      bodyLarge: const TextStyle(color: Colors.white),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.white,
      textColor: Colors.white,
    ),
  );
}
