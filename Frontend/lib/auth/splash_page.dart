import 'package:flutter/material.dart';
import '../auth/login_page.dart';
import '../features/meeting_screen.dart';
import '../services/auth_token.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: tryAutoLogin(), // ✅ 자동 로그인 시도
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == true) {
          return MeetingScreen(); // ✅ 자동 로그인 성공
        } else {
          return LoginPage(); // ❌ 로그인 필요
        }
      },
    );
  }
}
