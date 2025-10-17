// lib/widgets/bottom_chatbot_view.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../utils/ai_service.dart';
import 'package:flutter/services.dart';
import '../layout/bottom_section_controller.dart';

// 채팅 메시지를 위한 데이터 모델 (변경 없음)
class ChatMessage {
  final String text;
  final bool isUser;
  final List<String>? sourceFiles;

  ChatMessage({required this.text, required this.isUser, this.sourceFiles});
}

class BottomChatbotView extends StatefulWidget {
  const BottomChatbotView({super.key});

  @override
  State<BottomChatbotView> createState() => _BottomChatbotViewState();
}

// ✨ 1. AutomaticKeepAliveClientMixin 추가
class _BottomChatbotViewState extends State<BottomChatbotView>
    with AutomaticKeepAliveClientMixin<BottomChatbotView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  // 터미널 스타일 상수 (변경 없음)
  static const Color userTextColor = Color(0xFF333333);
  static const Color botTextColor = Color(0xFF006400);
  static const Color promptColor = Color(0xFF555555);
  static const String terminalFont = 'monospace';

  // ✨ 2. wantKeepAlive 오버라이드
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(text: 'Memordo Chatbot Ready.', isUser: false));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _controller.text;
    if (text.isEmpty) return;

    final isRagMode = context.read<BottomSectionController>().isRagMode;

    setState(() {
      _messages.add(ChatMessage(text: "> $text", isUser: true));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      if (isRagMode) {
        final response = await callRagTask(query: text);
        final responseText =
            response?['result']?.toString() ??
            (response?['error']?.toString() ??
                "[Error] Failed to get response.");
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
        });
      } else {
        final response = await callBackendTask(taskType: 'chat', text: text);
        setState(() {
          _isLoading = false;
          _messages.add(
            ChatMessage(
              text: response ?? "[Error] Failed to get response.",
              isUser: false,
            ),
          );
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add(
          ChatMessage(text: "[Error] ${e.toString()}", isUser: false),
        );
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.linear,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✨ 3. super.build(context) 호출 추가
    super.build(context);

    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final terminalBgColor =
        isDarkMode ? const Color(0xFF252526) : Colors.grey.shade100;

    return Container(
      color: terminalBgColor,
      padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
      child: Column(
        children: [Expanded(child: _buildMessagesArea()), _buildInputField()],
      ),
    );
  }

  Widget _buildMessagesArea() {
    return ListView.builder(
      controller: _scrollController,
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return _buildTypingIndicator();
        }
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final defaultTextColor =
        theme.textTheme.bodyMedium?.color ??
        (isDarkMode ? Colors.white70 : Colors.black87);
    final botTextColor =
        isDarkMode ? Colors.lightGreenAccent.shade200 : Colors.green.shade800;
    final textColor = message.isUser ? defaultTextColor : botTextColor;
    final displayText = message.isUser ? message.text : "🤖 ${message.text}";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: SelectableText(
        displayText,
        style: TextStyle(
          color: textColor,
          fontFamily: terminalFont,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final botTextColor =
        isDarkMode ? Colors.lightGreenAccent.shade200 : Colors.green.shade800;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Text(
            "🤖 ",
            style: TextStyle(
              color: botTextColor,
              fontFamily: terminalFont,
              fontSize: 13,
            ),
          ),
          TypingAnimation(),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Consumer<BottomSectionController>(
      builder: (context, controller, child) {
        final theme = Theme.of(context);
        final isDarkMode = theme.brightness == Brightness.dark;
        final ragTextColor =
            isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
        final ragActiveColor =
            isDarkMode
                ? Colors.lightGreenAccent.shade400
                : Colors.green.shade600;
        final inputTextColor =
            theme.textTheme.bodyMedium?.color ??
            (isDarkMode ? Colors.white70 : Colors.black87);
        final promptColor =
            isDarkMode ? Colors.grey.shade500 : Colors.grey.shade700;

        return Container(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "> ",
                    style: TextStyle(
                      color: promptColor,
                      fontFamily: terminalFont,
                      fontSize: 13,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      cursorColor: inputTextColor,
                      style: TextStyle(
                        color: inputTextColor,
                        fontFamily: terminalFont,
                        fontSize: 13,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: '메시지를 입력하세요...',
                        hintStyle: TextStyle(
                          color: Colors.grey,
                          fontFamily: terminalFont,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4.0),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '내 노트에서 검색',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: terminalFont,
                          color: ragTextColor,
                        ),
                      ),
                      Transform.scale(
                        scale: 0.7,
                        alignment: Alignment.centerRight,
                        child: Switch(
                          value: controller.isRagMode,
                          onChanged: (value) {
                            controller.setRagMode(value);
                          },
                          activeColor: ragActiveColor,
                          activeTrackColor: ragActiveColor.withOpacity(0.5),
                          inactiveThumbColor: Colors.grey.shade400,
                          inactiveTrackColor:
                              isDarkMode
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade200,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          trackOutlineColor: MaterialStateProperty.all(
                            Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// TypingAnimation (변경 없음)
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
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final cursorColor =
        theme.textTheme.bodyMedium?.color ??
        (isDarkMode ? Colors.white70 : Colors.black87);

    return FadeTransition(
      opacity: _controller,
      child: Container(width: 8, height: 14, color: cursorColor),
    );
  }
}
