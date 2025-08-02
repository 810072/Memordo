// Frontend/lib/features/settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'page_type.dart'; // PageType 임포트 유지

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    Color scaffoldBgColor = Theme.of(context).scaffoldBackgroundColor;

    return Container(
      color: scaffoldBgColor,
      child: Column(
        children: [
          PreferredSize(
            preferredSize: const Size.fromHeight(45.0),
            child: AppBar(
              title: const Text('Settings'),
              backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
              foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
              // ✨ [수정] elevation을 0으로 하고, shape를 사용하여 하단에 선을 추가합니다.
              elevation: 0,
              shape: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
              automaticallyImplyLeading: false,
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                SwitchListTile(
                  title: Text(
                    'Dark Mode',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                  value: themeProvider.themeMode == AppThemeMode.dark,
                  onChanged: (bool value) {
                    themeProvider.setThemeMode(
                      value ? AppThemeMode.dark : AppThemeMode.light,
                    );
                  },
                  secondary: Icon(
                    themeProvider.themeMode == AppThemeMode.dark
                        ? Icons.dark_mode
                        : Icons.light_mode,
                    color: Theme.of(context).listTileTheme.iconColor,
                  ),
                  activeColor: Theme.of(context).primaryColor,
                ),
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
