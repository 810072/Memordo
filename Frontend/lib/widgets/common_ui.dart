// lib/widgets/common_ui.dart

import 'package:flutter/material.dart';

/// 앱 전체에서 재사용 가능한 텍스트 입력 필드
Widget buildTextField({
  required TextEditingController controller,
  required String labelText,
  required IconData icon,
  bool obscureText = false,
  TextInputType? keyboardType,
  bool enabled = true,
  void Function(String)? onSubmitted,
  Color iconColor = const Color(0xFF475569),
  Color focusedBorderColor = const Color(0xFF3d98f4),
  Color fillColor = const Color(0xFFF1F5F9),
  double borderRadius = 12.0,
}) {
  return TextField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    enabled: enabled,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      labelText: labelText,
      prefixIcon: Icon(icon, color: iconColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: focusedBorderColor, width: 2.0),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      disabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 16.0,
        horizontal: 12.0,
      ),
    ),
    textInputAction:
        onSubmitted != null ? TextInputAction.done : TextInputAction.next,
  );
}

/// 앱 전체에서 재사용 가능한 로딩 상태를 포함하는 버튼
Widget buildElevatedButton({
  required String text,
  required VoidCallback? onPressed,
  bool isLoading = false,
  Color bgColor = const Color(0xFF3d98f4),
}) {
  return SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        elevation: 2,
        shadowColor: Colors.black38,
        disabledBackgroundColor: bgColor.withOpacity(0.4),
        disabledForegroundColor: Colors.white70,
      ),
      onPressed: onPressed,
      child:
          isLoading
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
              : Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
    ),
  );
}
