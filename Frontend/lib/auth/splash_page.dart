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
    // initState에서는 context를 직접 사용하기보다 addPostFrameCallback 사용 권장
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = Provider.of<TokenStatusProvider>(context, listen: false);
      await provider.loadFromCache();

      // 최소 2초 대기 (로딩이 빨리 끝나도 스플래시를 잠시 보여줌)
      await Future.delayed(const Duration(milliseconds: 2000));

      if (!mounted) return;
      if (provider.isLoaded) {
        Navigator.pushReplacementNamed(context, '/main');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
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
