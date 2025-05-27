import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../features/meeting_screen.dart';
import '../auth/login_page.dart';
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
    _init();
  }

  Future<void> _init() async {
    final tokenProvider = context.read<TokenStatusProvider>();
    await tokenProvider.loadStatus(context); // ✅ context 전달

    final status = tokenProvider.status;

    if (status != null &&
        (status.accessTokenValid || status.refreshTokenValid)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MeetingScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
