// Frontend/lib/features/settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
// import '../layout/main_layout.dart'; // MainLayout 임포트 유지
import 'page_type.dart'; // PageType 임포트 유지

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(
      context,
    ); // ThemeProvider에 접근

    // SettingsPage 자체의 배경색을 현재 활성화된 테마의 scaffoldBackgroundColor에서 가져옵니다.
    // 이는 이 페이지의 전체 배경색을 제어합니다.
    Color scaffoldBgColor = Theme.of(context).scaffoldBackgroundColor;

    return Container(
      // Scaffold 대신 Container를 사용하여 배경색을 직접 제어
      color: scaffoldBgColor, // SettingsPage의 배경색을 테마에 따라 설정
      child: Column(
        children: [
          AppBar(
            // SettingsPage 전용 AppBar
            title: const Text('Settings'),
            // AppBar의 색상을 현재 테마에서 가져오도록 명시적으로 설정합니다.
            backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
            foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
            elevation: Theme.of(context).appBarTheme.elevation,
          ),
          Expanded(
            child: ListView(
              children: [
                // SwitchListTile의 색상도 테마에 맞게 조정합니다.
                SwitchListTile(
                  title: Text(
                    'Dark Mode',
                    // 텍스트 색상을 현재 테마의 TextTheme.bodyMedium에서 가져옵니다.
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                  value:
                      themeProvider.themeMode ==
                      AppThemeMode.dark, // 현재 테마 모드를 기준으로 값 설정
                  onChanged: (bool value) {
                    themeProvider.setThemeMode(
                      value ? AppThemeMode.dark : AppThemeMode.light,
                    ); // 테마 모드 변경
                  },
                  secondary: Icon(
                    themeProvider.themeMode == AppThemeMode.dark
                        ? Icons.dark_mode
                        : Icons.light_mode,
                    // 아이콘 색상을 현재 테마의 ListTileTheme에서 가져옵니다.
                    color: Theme.of(context).listTileTheme.iconColor,
                  ),
                  activeColor: Theme.of(context).primaryColor, // 활성 상태일 때의 색상
                ),
                // 나머지 ListTile들도 테마에 맞게 색상을 조정합니다.
                ListTile(
                  leading: Icon(
                    Icons.person,
                    color: Theme.of(context).listTileTheme.iconColor,
                  ),
                  title: Text(
                    'Account',
                    style: TextStyle(
                      color: Theme.of(context).listTileTheme.textColor,
                    ),
                  ),
                  onTap: () {
                    // TODO: 계정 설정 페이지로 이동
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.lock,
                    color: Theme.of(context).listTileTheme.iconColor,
                  ),
                  title: Text(
                    'Privacy',
                    style: TextStyle(
                      color: Theme.of(context).listTileTheme.textColor,
                    ),
                  ),
                  onTap: () {
                    // TODO: 개인 정보 설정 페이지로 이동
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.notifications,
                    color: Theme.of(context).listTileTheme.iconColor,
                  ),
                  title: Text(
                    'Notifications',
                    style: TextStyle(
                      color: Theme.of(context).listTileTheme.textColor,
                    ),
                  ),
                  onTap: () {
                    // TODO: 알림 설정 페이지로 이동
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.info,
                    color: Theme.of(context).listTileTheme.iconColor,
                  ),
                  title: Text(
                    'About',
                    style: TextStyle(
                      color: Theme.of(context).listTileTheme.textColor,
                    ),
                  ),
                  onTap: () {
                    // TODO: 정보 페이지로 이동
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
