// Frontend/lib/features/chatbot_page.dart

import 'package:flutter/material.dart';
import '../utils/ai_service.dart'; // AI 서비스 임포트
import 'dart:async';

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
      _isLoading = false; // 로딩 종료
      _messages.add(
        ChatMessage(text: response ?? "오류가 발생했습니다.", isUser: false),
      );
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Red Hat Display'), // 폰트 적용
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F7F7), // 전체 배경색
        body: Center(
          child: Container(
            // 디자인의 .chat 컨테이너에 해당
            width: 360, // 창 크기에 맞게 조정
            height: 740,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 128,
                  offset: const Offset(0, 0),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 64,
                  spreadRadius: -48,
                  offset: const Offset(0, 32),
                ),
              ],
            ),
            child: Column(
              children: [
                // 상단 연락처 바
                _buildChatHeader(),
                // 채팅 메시지 목록
                Expanded(child: _buildMessagesArea()),
                // 하단 텍스트 입력 필드
                _buildInputField(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 상단 헤더 위젯
  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Color(0xFF3d98f4),
            child: Icon(Icons.smart_toy, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Memordo 챗봇',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
              ),
              SizedBox(height: 2),
              Text(
                'Online',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 메시지 영역 위젯
  Widget _buildMessagesArea() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: const Color(0xFFF7F7F7),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _messages.length + (_isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _messages.length && _isLoading) {
            return _buildTypingIndicator();
          }
          final message = _messages[index];
          return _buildMessageBubble(message);
        },
      ),
    );
  }

  // 메시지 버블 위젯
  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF333333) : Colors.white,
          borderRadius:
              isUser
                  ? const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(0),
                  )
                  : const BorderRadius.only(
                    topLeft: Radius.circular(0),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.075), blurRadius: 32),
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 16,
              spreadRadius: -16,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.66,
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : const Color(0xFF333333),
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  // 로딩(타이핑) 인디케이터 위젯
  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(0),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.075), blurRadius: 32),
          ],
        ),
        child: const TypingAnimation(), // 타이핑 애니메이션 위젯 사용
      ),
    );
  }

  // 텍스트 입력 필드 위젯
  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            // ✨ [수정] 아이콘 버튼들 제거
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 16,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 16,
                      spreadRadius: -16,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _controller,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Type your message here!',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8), // 텍스트 필드와 전송 버튼 사이 간격
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF3d98f4)),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

// 타이핑 애니메이션을 위한 별도의 StatefulWidget
class TypingAnimation extends StatefulWidget {
  const TypingAnimation({super.key});

  @override
  State<TypingAnimation> createState() => _TypingAnimationState();
}

class _TypingAnimationState extends State<TypingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return ScaleTransition(
          scale: Tween(begin: 0.5, end: 1.0).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Interval(0.1 * i, 0.3 + 0.1 * i, curve: Curves.easeInOut),
            ),
          ),
          child: const CircleAvatar(radius: 4, backgroundColor: Colors.grey),
        );
      }),
    );
  }
}
