// lib/auth/find_id_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class FindIdPage extends StatefulWidget {
  const FindIdPage({super.key});

  @override
  _FindIdPageState createState() => _FindIdPageState();
}

class _FindIdPageState extends State<FindIdPage> {
  final TextEditingController _emailController = TextEditingController();
  String _resultMessage = '';
  bool _isLoading = false;

  final String baseUrl = 'https://aidoctorgreen.com';
  final String apiPrefix = '/memo/api';

  Future<void> _findId(BuildContext context) async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      setState(() => _resultMessage = '올바른 이메일 주소를 입력해주세요.');
      _showStyledSnackBar(_resultMessage, isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = '';
    });

    final url = Uri.parse('$baseUrl$apiPrefix/check-email');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (responseBody.containsKey('isDuplicate') &&
            responseBody['isDuplicate'] is bool) {
          bool isDuplicate = responseBody['isDuplicate'];
          setState(() {
            if (isDuplicate) {
              _resultMessage =
                  '✅ 해당 이메일로 등록된 계정이 있습니다.\n(실제 아이디는 이메일로 전송됩니다 - *백엔드 구현 필요*)';
            } else {
              _resultMessage = '❌ 해당 이메일로 등록된 계정을 찾을 수 없습니다.';
            }
          });
        } else {
          setState(() => _resultMessage = '알 수 없는 API 응답 형식입니다.');
        }
      } else {
        final errorMessage = responseBody['message'] ?? '아이디 찾기에 실패했습니다.';
        setState(
          () => _resultMessage = '오류: $errorMessage (${response.statusCode})',
        );
      }
    } catch (e) {
      setState(() => _resultMessage = '네트워크 오류 또는 응답 처리 오류: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        if (_resultMessage.isNotEmpty) {
          _showStyledSnackBar(
            _resultMessage,
            isError:
                _resultMessage.contains('❌') ||
                _resultMessage.contains('오류') ||
                _resultMessage.contains('알 수 없는'),
          );
        }
      }
    }
  }

  void _showStyledSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        margin: const EdgeInsets.all(16.0),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('아이디 찾기'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1.0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 5.0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Container(
              width: 400,
              padding: const EdgeInsets.symmetric(
                horizontal: 32.0,
                vertical: 48.0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '아이디 찾기',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '가입 시 사용한 이메일 주소를 입력해주세요.\n계정 존재 유무를 알려드립니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 32),
                  if (_resultMessage.isNotEmpty && !_isLoading)
                    Container(
                      padding: const EdgeInsets.all(12.0),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color:
                            _resultMessage.contains('✅')
                                ? Colors.green.shade50
                                : (_resultMessage.contains('❌') ||
                                    _resultMessage.contains('오류') ||
                                    _resultMessage.contains('알 수 없는'))
                                ? Colors.red.shade50
                                : Colors.blue.shade50, // 기본 메시지용
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color:
                              _resultMessage.contains('✅')
                                  ? Colors.green.shade200
                                  : (_resultMessage.contains('❌') ||
                                      _resultMessage.contains('오류') ||
                                      _resultMessage.contains('알 수 없는'))
                                  ? Colors.red.shade200
                                  : Colors.blue.shade200,
                        ),
                      ),
                      child: Text(
                        _resultMessage,
                        // ✅ TextStyle에서 const 제거 (color가 동적이므로)
                        style: TextStyle(
                          fontSize: 14, // 폰트 크기 일관성
                          // 여기서 사용되는 Colors.green, Colors.red 등은 const이지만,
                          // 삼항 연산자 때문에 전체 color 표현식은 const가 아님.
                          color:
                              _resultMessage.contains('✅')
                                  ? Colors
                                      .green
                                      .shade800 // .shadeXXX는 const가 아님
                                  : (_resultMessage.contains('❌') ||
                                      _resultMessage.contains('오류') ||
                                      _resultMessage.contains('알 수 없는'))
                                  ? Colors
                                      .red
                                      .shade800 // .shadeXXX는 const가 아님
                                  : Colors
                                      .blue
                                      .shade800, // .shadeXXX는 const가 아님
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  _buildTextField(
                    controller: _emailController,
                    labelText: '등록된 이메일 주소',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 24),
                  _buildElevatedButton(
                    text: '아이디 찾기',
                    onPressed: _isLoading ? null : () => _findId(context),
                    isLoading: _isLoading,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.deepPurple, width: 2.0),
          borderRadius: BorderRadius.circular(8.0),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8.0),
        ),
        filled: !enabled,
        fillColor: Colors.grey.shade100,
      ),
    );
  }

  Widget _buildElevatedButton({
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
    Color bgColor = Colors.deepPurple,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          elevation: 4,
          disabledBackgroundColor: bgColor.withOpacity(0.5),
        ),
        onPressed: isLoading ? null : onPressed,
        child:
            isLoading
                ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
                // ✅ 여기의 TextStyle은 내부 값들이 모두 const이므로 const로 유지 가능
                : Text(
                  text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
      ),
    );
  }
}
