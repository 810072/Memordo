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
    primaryColor: const Color(0xFF3d98f4),
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1E293B),
      elevation: 0,
    ),
    cardColor: const Color(0xFFF8F9FA),
    // ✨ [수정] 구분선 색상을 더 연한 회색으로 변경합니다.
    dividerColor: const Color(0xFFEAECEE),
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
    scaffoldBackgroundColor: const Color(0xFF121212), // 더 진한 검정
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF1E1E1E), // 어두운 회색
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardColor: const Color(0xFF1E1E1E),
    dividerColor: Colors.grey.shade800, // 다크모드용 구분선 색상
    textTheme: TextTheme(
      bodyMedium: const TextStyle(color: Colors.white70),
      titleMedium: const TextStyle(color: Colors.white70),
      bodyLarge: const TextStyle(color: Colors.white),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.white70,
      textColor: Colors.white,
    ),
  );
}
