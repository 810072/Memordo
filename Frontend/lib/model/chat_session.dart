// lib/model/chat_session.dart
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'chat_message_model.dart';

class ChatSession {
  String id;
  String title;
  List<ChatMessage> messages;

  ChatSession({required this.id, required this.title, required this.messages});

  factory ChatSession.createNew() {
    return ChatSession(
      id: const Uuid().v4(),
      title: '새 대화', // 기본 제목
      messages: [
        const ChatMessage(text: 'Memordo 챗봇입니다. 무엇을 도와드릴까요?', isUser: false),
      ],
    );
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String,
      messages:
          (json['messages'] as List<dynamic>)
              .map(
                (msgJson) =>
                    ChatMessage.fromJson(msgJson as Map<String, dynamic>),
              )
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((msg) => msg.toJson()).toList(),
    };
  }
}
