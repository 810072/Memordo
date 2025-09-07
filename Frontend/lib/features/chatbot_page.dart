// Frontend/lib/features/chatbot_page.dart

import 'package:flutter/material.dart';
import '../utils/ai_service.dart'; // AI 서비스 임포트
import 'dart:async';

// 채팅 메시지를 위한 데이터 모델
class ChatMessage {
  final String text;
  final bool isUser;
  final List<String>? sourceFiles; // RAG 소스 파일을 위한 필드 추가

  ChatMessage({required this.text, required this.isUser, this.sourceFiles});
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
  List<String> _currentSourceFiles = []; // 사이드 패널을 위한 상태 변수

  // [수정 1] RAG 모드 활성화를 위한 상태 변수를 추가합니다.
  bool _isRagMode = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(text: '안녕하세요! Memordo 챗봇입니다. 무엇을 도와드릴까요?', isUser: false),
    );
  }

  // [수정 2] RAG 모드에 따라 다른 함수를 호출하도록 로직을 변경합니다.
  void _sendMessage() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    // RAG 모드 여부에 따라 분기
    if (_isRagMode) {
      final response = await callRagTask(query: text);
      final responseText =
          response?['result']?.toString() ??
          (response?['error']?.toString() ?? "오류가 발생했습니다.");
      final List<String>? sourceFiles =
          (response?['sources'] as List?)
              ?.map((item) => item.toString())
              .toList();

      setState(() {
        _isLoading = false;
        _messages.add(
          ChatMessage(
            text: responseText,
            isUser: false,
            sourceFiles: sourceFiles,
          ),
        );
        // 사이드 패널의 상태를 업데이트
        _currentSourceFiles = sourceFiles ?? [];
      });
    } else {
      final response = await callBackendTask(taskType: 'chat', text: text);
      setState(() {
        _isLoading = false;
        _messages.add(
          ChatMessage(text: response ?? "오류가 발생했습니다.", isUser: false),
        );
        // 일반 채팅 시에는 소스 패널을 비웁니다.
        _currentSourceFiles = [];
      });
    }
    _scrollToBottom();
  }

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
      theme: ThemeData(fontFamily: 'Red Hat Display'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        body: Center(
          child: Container(
            height: 740,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 128,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 64,
                  spreadRadius: -48,
                  offset: const Offset(0, 32),
                ),
              ],
            ),
            child: Row(
              children: [
                // Main chat area
                Expanded(
                  child: Column(
                    children: [
                      _buildChatHeader(),
                      Expanded(child: _buildMessagesArea()),
                      _buildInputField(),
                    ],
                  ),
                ),
                // Divider and Sources panel (conditional)
                if (_currentSourceFiles.isNotEmpty)
                  Container(width: 1, color: Colors.grey.shade200),
                if (_currentSourceFiles.isNotEmpty) _buildSourcesPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
        child: const TypingAnimation(),
      ),
    );
  }

  // [수정 3] RAG 스위치를 포함하도록 입력 필드 위젯 구조를 Column으로 변경합니다.
  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
      color: Colors.white,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 기존 입력 필드와 전송 버튼 Row
            Row(
              children: [
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
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF3d98f4)),
                  onPressed: _sendMessage,
                ),
              ],
            ),
            // RAG 스위치 Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '내 노트에서 검색',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: _isRagMode,
                  onChanged: (value) {
                    setState(() {
                      _isRagMode = value;
                    });
                  },
                  activeColor: const Color(0xFF3d98f4),
                  inactiveThumbColor: Colors.grey.shade400,
                  inactiveTrackColor: Colors.grey.shade200,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesPanel() {
    return Container(
      width: 200,
      color: const Color(0xFFF0F2F5),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '참조 문서',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          if (_currentSourceFiles.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  '표시할 참조 문서가\n없습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _currentSourceFiles.length,
                itemBuilder: (context, index) {
                  final file = _currentSourceFiles[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.description,
                          size: 16,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            file,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: CircleAvatar(
              radius: 4,
              backgroundColor: Colors.grey.shade400,
            ),
          ),
        );
      }),
    );
  }
}
