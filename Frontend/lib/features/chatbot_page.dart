// Frontend/lib/features/chatbot_page.dart

import 'package:flutter/material.dart';
import '../utils/ai_service.dart'; // AI 서비스 임포트

// 채팅 메시지를 위한 데이터 모델
class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 초기 메시지 추가
    _messages.add(
      ChatMessage(text: '안녕하세요! Memordo 챗봇입니다. 무엇을 도와드릴까요?', isUser: false),
    );
  }

  // 메시지 전송 및 AI 응답 처리 함수
  void _sendMessage() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    // 사용자의 메시지를 화면에 추가
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true; // 로딩 시작
    });
    _controller.clear();
    _scrollToBottom();

    // AI 서비스 호출
    final response = await callBackendTask(taskType: 'chat', text: text);

    // AI의 응답을 화면에 추가
    setState(() {
      _messages.add(
        ChatMessage(text: response ?? "오류가 발생했습니다.", isUser: false),
      );
      _isLoading = false; // 로딩 종료
    });
    _scrollToBottom();
  }

  // 스크롤을 맨 아래로 이동시키는 함수
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // MaterialApp을 최상위로 유지하여 독립적인 테마 및 네비게이션을 가짐
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        fontFamily: 'Pretendard',
      ),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1.0,
          title: const Text(
            'Memordo 챗봇',
            style: TextStyle(
              color: Color(0xFF1E293B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Column(
          children: [
            // 채팅 메시지 목록
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16.0),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return _buildMessageBubble(message);
                },
              ),
            ),
            // 로딩 인디케이터
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: LinearProgressIndicator(),
              ),
            // 하단 텍스트 입력 필드
            _buildInputField(),
          ],
        ),
      ),
    );
  }

  // 메시지 버블 위젯
  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5.0),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: message.isUser ? const Color(0xFF3d98f4) : Colors.white,
          borderRadius: BorderRadius.circular(20.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              spreadRadius: 1,
              blurRadius: 3,
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : const Color(0xFF334155),
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  // 텍스트 입력 필드 위젯
  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: '메시지를 입력하세요...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8.0),
                ),
                minLines: 1,
                maxLines: 5,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF3d98f4)),
              onPressed: _sendMessage,
              tooltip: '전송',
            ),
          ],
        ),
      ),
    );
  }
}
