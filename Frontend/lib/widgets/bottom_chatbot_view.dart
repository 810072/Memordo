// lib/widgets/bottom_chatbot_view.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../utils/ai_service.dart';
import 'package:flutter/services.dart';
import '../layout/bottom_section_controller.dart';
import '../providers/chat_session_provider.dart';
import '../model/chat_message_model.dart';

class BottomChatbotView extends StatefulWidget {
  const BottomChatbotView({super.key});

  @override
  State<BottomChatbotView> createState() => _BottomChatbotViewState();
}

class _BottomChatbotViewState extends State<BottomChatbotView>
    with AutomaticKeepAliveClientMixin<BottomChatbotView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  static const String terminalFont = 'monospace';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // _sendMessage, _scrollToBottom 메서드는 이전과 동일
  void _sendMessage() async {
    final chatProvider = context.read<ChatSessionProvider>();
    final text = _controller.text;
    final activeSession = chatProvider.activeSession;
    if (text.isEmpty || activeSession == null) return;

    final isRagMode = context.read<BottomSectionController>().isRagMode;
    // '> ' 접두사를 여기서 추가합니다.
    final userMessage = ChatMessage(text: "> $text", isUser: true);
    chatProvider.addMessageToActiveSession(userMessage);

    setState(() {
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    final updatedHistory = chatProvider.activeSession?.messages ?? [];

    try {
      ChatMessage botMessage;
      if (isRagMode) {
        final response = await callRagTask(
          query: text,
          history: updatedHistory,
        );
        final responseText =
            response?['result']?.toString() ??
            response?['error']?.toString() ??
            "[Error] Failed to get response.";
        final List<String>? sourceFiles =
            (response?['sources'] as List?)
                ?.map((item) => item.toString())
                .toList();
        botMessage = ChatMessage(
          text: responseText,
          isUser: false,
          sourceFiles: sourceFiles,
        );
      } else {
        final response = await callBackendTask(
          taskType: 'chat',
          text: text,
          history: updatedHistory,
        );
        botMessage = ChatMessage(
          text: response ?? "[Error] Failed to get response.",
          isUser: false,
        );
      }
      chatProvider.addMessageToActiveSession(botMessage);
    } catch (e) {
      final errorMessage = ChatMessage(
        text: "[Error] ${e.toString()}",
        isUser: false,
      );
      chatProvider.addMessageToActiveSession(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
    super.build(context);

    final theme = Theme.of(context);

    return Consumer<ChatSessionProvider>(
      builder: (context, chatProvider, child) {
        // 최상위 Container의 color 속성을 제거하여 부모 위젯(main_layout.dart)의 색상을 상속받도록 합니다.
        return Container(
          child: Row(
            children: [
              // --- 1. 메인 채팅 영역 (메시지 + 입력 필드) ---
              Expanded(
                child: Padding(
                  // bottom 패딩을 0.0으로 변경하여 바닥에 붙도록 함
                  padding: const EdgeInsets.only(
                    top: 8.0,
                    left: 8.0,
                    right: 8.0,
                    bottom: 0.0, // 수정됨
                  ),
                  child: Column(
                    children: [
                      // 메시지 영역만 Expanded로 감싸서 남은 공간을 모두 차지하도록 함
                      Expanded(child: _buildMessagesArea(chatProvider)),
                      // 입력 필드는 Expanded 밖에 두어 Column의 하단에 위치하도록 함
                      _buildInputField(chatProvider),
                    ],
                  ),
                ),
              ),
              // --- 2. 세로 구분선 ---
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: theme.dividerColor.withOpacity(0.5),
              ),
              // --- 3. 우측 세션 목록 영역 ---
              // color 속성을 제거하여 부모 위젯의 색상을 상속받도록 합니다.
              Container(
                width: 180, // 세션 목록 너비 지정 (조절 가능)
                child: _buildSessionList(context, chatProvider, theme),
              ),
            ],
          ),
        );
      },
    );
  }

  // _buildMessagesArea, _buildMessageBubble, _buildTypingIndicator 메서드는 이전과 동일
  Widget _buildMessagesArea(ChatSessionProvider chatProvider) {
    final messages = chatProvider.activeSession?.messages ?? [];
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return ListView.builder(
      controller: _scrollController,
      itemCount: messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length && _isLoading) {
          return _buildTypingIndicator();
        }
        if (index >= messages.length) return const SizedBox.shrink();
        final message = messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    // 텍스트 색상을 테마에 맞게 조정
    final defaultTextColor =
        theme.textTheme.bodyMedium?.color ??
        (isDarkMode ? Colors.white70 : Colors.black87);
    final botTextColor =
        isDarkMode ? Colors.lightGreenAccent.shade200 : Colors.green.shade800;
    final userTextColor =
        isDarkMode ? Colors.blue.shade200 : Colors.blue.shade800;

    final textColor = message.isUser ? userTextColor : botTextColor;
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

  // ✨ [수정] 입력 필드와 RAG 스위치를 하나의 Row에 배치 + 구분선 제거
  Widget _buildInputField(ChatSessionProvider chatProvider) {
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

        // 입력 텍스트 색상을 메시지 버블과 맞춤
        final inputTextColor =
            isDarkMode ? Colors.blue.shade200 : Colors.blue.shade800;

        final promptColor =
            isDarkMode ? Colors.grey.shade500 : Colors.grey.shade700;

        // Row 로 변경
        return Container(
          // ✨ [삭제] decoration 속성 제거 (구분선 제거)
          // decoration: BoxDecoration(
          //   border: Border(
          //     top: BorderSide(color: theme.dividerColor.withOpacity(0.5), width: 1.0),
          //   ),
          // ),
          // 내부 패딩 조정
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center, // 세로 중앙 정렬
            children: [
              // --- 프롬프트 + 입력 필드 ---
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
                    contentPadding: EdgeInsets.symmetric(vertical: 6.0),
                  ),
                ),
              ),
              // --- RAG 스위치 ---
              Row(
                mainAxisSize: MainAxisSize.min, // 필요한 만큼만 너비 차지
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
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      trackOutlineColor: MaterialStateProperty.all(
                        Colors.transparent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // 우측 세션 목록 UI (_buildSessionList) - 이전과 동일
  Widget _buildSessionList(
    BuildContext context,
    ChatSessionProvider chatProvider,
    ThemeData theme,
  ) {
    final isDarkMode = theme.brightness == Brightness.dark;
    // listBgColor 속성을 제거하여 부모의 색상을 상속받도록 합니다.

    return Column(
      children: [
        // --- 세션 목록 헤더 ---
        Container(
          height: 36, // 헤더 높이
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withOpacity(0.5),
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '대화 목록',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                  letterSpacing: 0.5,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                tooltip: '새 대화 시작',
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => chatProvider.createNewSession(),
                color: theme.iconTheme.color?.withOpacity(0.8),
              ),
            ],
          ),
        ),
        // --- 세션 목록 ---
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            itemCount: chatProvider.sessions.length,
            itemBuilder: (context, index) {
              final session = chatProvider.sessions[index];
              final isActive = chatProvider.activeSession?.id == session.id;

              return Material(
                color:
                    isActive
                        ? theme.primaryColor.withOpacity(0.1)
                        : Colors.transparent,
                child: InkWell(
                  onTap: () => chatProvider.setActiveSession(session.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 6.0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: terminalFont,
                              color:
                                  isActive
                                      ? theme.primaryColor
                                      : theme.textTheme.bodyMedium?.color
                                          ?.withOpacity(0.8),
                              fontWeight:
                                  isActive
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        // --- 삭제 버튼 다이얼로그 (이전과 동일) ---
                        if (chatProvider.sessions.length > 1)
                          InkWell(
                            onTap: () {
                              showDialog<bool>(
                                context: context,
                                builder: (ctx) {
                                  final dialogTheme = Theme.of(ctx);
                                  final isDialogDarkMode =
                                      dialogTheme.brightness == Brightness.dark;

                                  return AlertDialog(
                                    backgroundColor:
                                        isDialogDarkMode
                                            ? const Color(0xFF2E2E2E)
                                            : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                      side: BorderSide(
                                        color:
                                            isDialogDarkMode
                                                ? Colors.grey.shade700
                                                : Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                    ),
                                    title: Text(
                                      '대화 삭제',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color:
                                            isDialogDarkMode
                                                ? Colors.white
                                                : Colors.black,
                                      ),
                                    ),
                                    content: Text(
                                      '\'${session.title}\' 대화를 정말 삭제하시겠습니까?',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color:
                                            isDialogDarkMode
                                                ? Colors.grey.shade400
                                                : Colors.grey.shade600,
                                      ),
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        child: const Text(
                                          '취소',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onPressed:
                                            () => Navigator.of(ctx).pop(false),
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              isDialogDarkMode
                                                  ? Colors.white70
                                                  : Colors.black54,
                                        ),
                                      ),
                                      ElevatedButton(
                                        child: const Text(
                                          '삭제',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        onPressed:
                                            () => Navigator.of(ctx).pop(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFE57373,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8.0,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ).then((confirmed) {
                                if (confirmed == true) {
                                  chatProvider.deleteSession(session.id);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color:
                                    isActive
                                        ? theme.primaryColor.withOpacity(0.8)
                                        : theme.iconTheme.color?.withOpacity(
                                          0.5,
                                        ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
