// lib/model/chat_message_model.dart
import 'package:flutter/foundation.dart';

// 기존 ChatMessage 클래스를 별도 파일로 분리하고,
// JSON 직렬화를 위한 toJson/fromJson 팩토리 메서드 추가

@immutable
class ChatMessage {
  final String text;
  final bool isUser;
  final List<String>? sourceFiles;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.sourceFiles,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] as String,
      isUser: json['isUser'] as bool,
      sourceFiles:
          (json['sourceFiles'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'text': text, 'isUser': isUser, 'sourceFiles': sourceFiles};
  }
}
