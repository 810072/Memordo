import 'dart:io' show File, Directory, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p; // path 패키지 import 별칭 사용
// import 'dart:html' as html;

import '../layout/bottom_section.dart';
import '../layout/left_sidebar_layout.dart';
import '../utils/web_helper.dart'; // 웹 다운로드 헬퍼
import '../utils/ai_service.dart'; // AI 서비스 import (경로 확인!)

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final TextEditingController _textEditingController =
      TextEditingController(); // 이름 변경 (더 명확하게)
  String _saveStatus = ''; // 파일 저장 상태 메시지
  // String _summaryStatus = ''; // 요약 상태 메시지 (BottomSection에서 관리)

  bool _isSummarizing = false; // AI 요약 작업 진행 상태
  final GlobalKey<CollapsibleBottomSectionState> _bottomSectionKey =
      GlobalKey();

  /// ✅ 원하는 저장 경로 설정 (macOS 전용)
  Future<String> getCustomSavePath() async {
    // 웹 환경에서는 이 함수가 호출되지 않도록 kIsWeb 체크가 _saveMarkdown에 있음
    if (Platform.isMacOS) {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE']; // Windows HOME도 고려
      final folderPath = p.join(
        home!,
        'Memordo_Notes',
      ); // path 패키지 사용, 폴더명 변경 가능
      final directory = Directory(folderPath);

      if (!await directory.exists()) {
        await directory.create(recursive: true);
        print('폴더 생성됨: $folderPath');
      }
      return folderPath;
    }
    // 다른 플랫폼에 대한 기본 경로 (예: Documents 폴더)는 추가 구현 필요
    // 지금은 macOS 외에는 지원되지 않음을 알림
    throw UnsupportedError('현재 macOS에서만 사용자 정의 경로 저장을 지원합니다.');
  }

  Future<void> _saveMarkdown() async {
    final content = _textEditingController.text;
    if (content.isEmpty) {
      if (!mounted) return;
      setState(() {
        _saveStatus = "저장할 내용이 없습니다.";
      });
      return;
    }

    if (kIsWeb) {
      downloadMarkdownWeb(
        content,
        'memordo_note_${DateTime.now().millisecondsSinceEpoch}.md',
      ); // 두 개의 인자 전달
      if (!mounted) return;
      setState(() {
        _saveStatus = "웹에서 다운로드를 시작합니다 ✅";
      });
    } else if (Platform.isMacOS) {
      // 다른 데스크톱 플랫폼 지원 시 else if (Platform.isWindows || Platform.isLinux) 추가
      try {
        final saveDir = await getCustomSavePath();
        final fileName = 'note_${DateTime.now().millisecondsSinceEpoch}.md';
        final filePath = p.join(saveDir, fileName); // path 패키지 사용

        final file = File(filePath);
        await file.writeAsString(content);
        if (!mounted) return;
        setState(() {
          _saveStatus = "저장 완료: $filePath";
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _saveStatus = "파일 저장 오류 ❌: $e";
        });
      }
    } else {
      if (!mounted) return;
      setState(() {
        _saveStatus =
            "${Platform.operatingSystem} 플랫폼은 아직 파일 저장 기능이 지원되지 않습니다 🛑";
      });
    }
  }

  // --- AI 요약 처리 함수 ---
  Future<void> _handleSummarizeAction() async {
    if (_isSummarizing) return; // 이미 요약 중이면 중복 실행 방지

    final String textToSummarize = _textEditingController.text;

    if (textToSummarize.trim().isEmpty) {
      _bottomSectionKey.currentState?.updateSummary('요약할 내용이 없습니다.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('요약할 내용을 먼저 입력해주세요.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSummarizing = true;
    });
    // BottomSection의 텍스트를 "요약 중..."으로 먼저 업데이트
    _bottomSectionKey.currentState?.updateSummary(
      '텍스트 요약 중...\n입력된 내용 길이: ${textToSummarize.length}',
    );

    String? summary;
    try {
      // ai_service.dart의 callBackendTask 함수 사용
      summary = await callBackendTask(
        taskType: "summarize", // 백엔드에서 정의된 요약 작업 유형
        text: textToSummarize,
      );
    } catch (e) {
      print('❌ 요약 API 호출 중 예외 발생: $e');
      summary = '요약 중 오류가 발생했습니다: $e';
    } finally {
      if (!mounted) return;
      _bottomSectionKey.currentState?.updateSummary(
        summary ?? '요약에 실패했거나 내용이 없습니다.',
      );
      setState(() {
        _isSummarizing = false;
      });
    }

    // 요약 실패 또는 오류 시 스낵바 표시 (선택적)
    if (summary == null || summary.contains("오류") || summary.contains("실패")) {
      print('❌ 요약 실패 또는 오류 수신: $summary');
      if (mounted) {
        // mounted 체크 후 context 사용
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(summary ?? '텍스트 요약에 실패했습니다.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LeftSidebarLayout(
      activePage: PageType.home, // PageType은 정의된 enum 값 사용
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, // 자식 요소들이 가로로 꽉 차도록
        children: [
          Container(
            height: 40,
            color: Colors.grey[300],
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              '메인 화면 - 새 메모 작성', // 타이틀 변경
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textEditingController,
                      maxLines:
                          null, // null로 설정해야 여러 줄 입력 및 expands: true와 함께 작동
                      expands: true, // TextField가 사용 가능한 모든 공간을 차지하도록 함
                      textAlignVertical: TextAlignVertical.top, // 텍스트를 위에서부터 시작
                      decoration: const InputDecoration(
                        hintText: '여기에 글을 작성하세요...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12), // 내부 패딩 추가
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                      ), // 폰트 크기 및 줄 간격
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start, // 버튼들을 왼쪽으로 정렬
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save_alt_outlined, size: 18),
                        label: const Text('.md 파일로 저장'),
                        onPressed: _saveMarkdown,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[700],
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        // 상태 메시지가 남은 공간을 채우도록
                        child: Text(
                          _saveStatus,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            overflow: TextOverflow.ellipsis, // 메시지가 길면 생략 부호
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          CollapsibleBottomSection(
            key: _bottomSectionKey, // GlobalKey 전달
            onSummarizePressed:
                _isSummarizing ? null : _handleSummarizeAction, // 콜백 전달
            isLoading: _isSummarizing, // 로딩 상태 전달
          ),
        ],
      ),
    );
  }
}
