import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';

/// 웹사이트를 크롤링해 Markdown 형식으로 저장하고 경로를 반환 (데스크탑용)
Future<String?> crawlAndSaveAsMarkdown(
  String url, {
  String? customFileName,
}) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      print('요청 실패: ${response.statusCode}');
      return null;
    }

    final Document document = parser.parse(response.body);
    final StringBuffer mdBuffer = StringBuffer();

    final title = document.querySelector('title')?.text.trim() ?? 'No Title';
    mdBuffer.writeln('# $title\n');

    for (int i = 1; i <= 3; i++) {
      for (final h in document.querySelectorAll('h$i')) {
        mdBuffer.writeln('${'#' * i} ${h.text.trim()}\n');
      }
    }

    for (final p in document.querySelectorAll('p')) {
      final text = p.text.trim();
      if (text.isNotEmpty) mdBuffer.writeln('$text\n');
    }

    // 👇 현재 실행 디렉토리에 mdstore 디렉토리 생성
    final Directory mdStoreDir = Directory('mdstore');
    if (!await mdStoreDir.exists()) {
      await mdStoreDir.create(recursive: true);
    }

    final safeFilename =
        (customFileName ?? title)
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .replaceAll(' ', '_')
            .toLowerCase();

    final filePath = '${mdStoreDir.path}/$safeFilename.md';
    final File file = File(filePath);
    await file.writeAsString(mdBuffer.toString());

    print('✅ (Web_craler.dart)Markdown 저장 완료: $filePath');
    return filePath;
  } catch (e) {
    print('❌ (Web_craler.dart)에러 발생: $e');
    return null;
  }
}
