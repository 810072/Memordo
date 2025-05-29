// lib/auth/splash_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/token_status_provider.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final provider = Provider.of<TokenStatusProvider>(context, listen: false);
    await provider.loadStatus(context); // ✅ 반드시 호출!

    print('⏳ 캐시에서 토큰 불러오는 중...');
    await provider.loadFromCache();

    if (!provider.isAuthenticated) {
      print('🟥 캐시에 유효한 accessToken 없음 → 로그인 이동');
      await provider.forceLogout(context);
      return;
    }

    try {
      print('🌐 서버로 토큰 유효성 확인 중...');
      await provider.loadStatus(context); // 여기서 fetchTokenStatus 내부 호출

      if (!mounted) return;

      if (provider.isAuthenticated) {
        print('🟢 서버 인증 완료 → 메인 화면');
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        print('🟡 서버 응답으로 accessToken 무효 → 로그인 이동');
        await provider.forceLogout(context);
      }
    } catch (e) {
      print('❌ 예외 발생 (토큰 오류 또는 네트워크 문제): $e');
      await provider.forceLogout(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // 부드러운 배경색
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 로고 (assets/logo.png 파일이 필요합니다)
            Image.asset('assets/logo.png', width: 120, height: 120),
            const SizedBox(height: 32),
            const Text(
              "Memordo",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Your intelligent memo assistant.",
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 48),
            CircularProgressIndicator(color: Colors.deepPurple.shade300),
            const SizedBox(height: 16),
            Text(
              "Loading...",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
