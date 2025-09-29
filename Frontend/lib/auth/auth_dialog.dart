// lib/auth/auth_dialog.dart
import 'package:flutter/material.dart';
import 'login_form.dart';
import 'signup_form.dart';
import 'email_check_form.dart';
import 'find_id_form.dart';
import 'password_reset_form.dart';

// 현재 보여줄 인증 폼의 종류를 나타내는 열거형
enum AuthView { login, signup, findId, emailCheck, passwordReset }

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key});

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  // 현재 보여줄 뷰를 'login'으로 초기화
  AuthView _currentView = AuthView.login;
  // 비밀번호 재설정을 위해 이메일 주소를 임시 저장할 변수
  String _emailForPasswordReset = '';

  // 다른 폼으로 화면을 전환하는 함수
  void _changeView(AuthView newView, {String email = ''}) {
    setState(() {
      _currentView = newView;
      // 비밀번호 재설정 폼으로 전환될 경우, 이메일 값을 저장
      if (newView == AuthView.passwordReset) {
        _emailForPasswordReset = email;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget currentForm;
    // _currentView 값에 따라 적절한 폼 위젯을 선택
    switch (_currentView) {
      case AuthView.login:
        currentForm = LoginForm(
          onGoToSignup: () => _changeView(AuthView.signup),
          onGoToFindId: () => _changeView(AuthView.findId),
          onGoToEmailCheck: () => _changeView(AuthView.emailCheck),
        );
        break;
      case AuthView.signup:
        currentForm = SignupForm(
          onGoToLogin: () => _changeView(AuthView.login),
        );
        break;
      case AuthView.findId:
        currentForm = FindIdForm(
          onGoToLogin: () => _changeView(AuthView.login),
        );
        break;
      case AuthView.emailCheck:
        currentForm = EmailCheckForm(
          onGoToLogin: () => _changeView(AuthView.login),
          onEmailVerified:
              (email) => _changeView(AuthView.passwordReset, email: email),
        );
        break;
      case AuthView.passwordReset:
        currentForm = PasswordResetForm(
          email: _emailForPasswordReset,
          onGoToLogin: () => _changeView(AuthView.login),
        );
        break;
    }

    // ✨ [추가] 현재 테마의 밝기를 확인합니다.
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // ✨ [추가] 테마에 따라 아이콘 색상을 결정합니다.
    final iconColor = isDarkMode ? Colors.white70 : Colors.black54;

    // Dialog 위젯으로 전체 폼을 감싸서 반환
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Stack(
        children: [
          SingleChildScrollView(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: currentForm,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: IconButton(
              icon: Icon(Icons.close, color: iconColor), // ✨ [수정] 테마에 맞는 색상 적용
              onPressed: () => Navigator.of(context).pop(),
              tooltip: '닫기',
            ),
          ),
        ],
      ),
    );
  }
}
