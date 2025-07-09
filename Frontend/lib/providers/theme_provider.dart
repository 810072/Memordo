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
  ThemeData _lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: const Color(0xFF3d98f4), // 앱의 주요 색상
    scaffoldBackgroundColor: const Color(0xFFF1F5F9), // 스캐폴드 배경색
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white, // 앱바 배경색
      foregroundColor: Color(0xFF1E293B), // 앱바 전경색 (아이콘, 텍스트)
      elevation: 1.0, // 앱바 그림자
    ),
    cardColor: Colors.white, // 카드 위젯 배경색
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: Colors.grey.shade800), // 본문 텍스트 색상
      titleMedium: TextStyle(color: Colors.grey.shade700), // 제목 텍스트 색상
      bodyLarge: TextStyle(color: Colors.grey.shade800), // 큰 본문 텍스트 색상
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.black54, // 리스트 타일 아이콘 색상
      textColor: Colors.black87, // 리스트 타일 텍스트 색상
    ),
    // 다른 라이트 테마 속성들을 여기에 추가할 수 있습니다.
  );

  // 다크 테마 정의
  ThemeData _darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.deepPurple.shade300, // 앱의 주요 색상 (다크 모드용)
    scaffoldBackgroundColor: const Color(0xFF12182B), // 스캐폴드 배경색을 더 진하게
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF1E273B), // 앱바 배경색을 더 진하게
      foregroundColor: Colors.white, // 앱바 전경색을 흰색으로
      elevation: 1.0,
    ),
    cardColor: const Color(0xFF1E273B), // 카드 위젯 배경색을 앱바와 동일하게 더 진하게
    textTheme: TextTheme(
      bodyMedium: const TextStyle(color: Colors.white), // 본문 텍스트 색상을 흰색으로
      titleMedium: const TextStyle(color: Colors.white), // 제목 텍스트 색상을 흰색으로
      bodyLarge: const TextStyle(color: Colors.white), // 큰 본문 텍스트 색상을 흰색으로
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.white, // 리스트 타일 아이콘 색상을 흰색으로
      textColor: Colors.white, // 리스트 타일 텍스트 색상을 흰색으로
    ),
    // 다른 다크 테마 속성들을 여기에 추가할 수 있습니다.
  );
}
