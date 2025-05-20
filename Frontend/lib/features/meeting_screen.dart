import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart'; // Provider 임포트

import '../layout/bottom_section.dart';
import '../layout/left_sidebar_layout.dart';
import '../utils/web_helper.dart';
import '../utils/ai_service.dart';
import '../layout/bottom_section_controller.dart'; // 컨트롤러 임포트

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final TextEditingController _textEditingController = TextEditingController();
  String _saveStatus = '';
  // _isSummarizing은 이제 BottomSectionController에서 관리됩니다.
  // bool _isSummarizing = false;
  // GlobalKey 대신 BottomSectionController를 직접 사용합니다.
  // final GlobalKey<CollapsibleBottomSectionState> _bottomSectionKey = GlobalKey();
  String? _lastSavedDirectoryPath;

  /// ✅ 사용자 홈에 Memordo_Notes 폴더가 없으면 생성하고 경로 반환
  Future<String> getOrCreateNoteFolderPath() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];

    if (home == null) {
      throw Exception('사용자 홈 디렉터리를 찾을 수 없습니다.');
    }

    final folderPath =
        Platform.isMacOS
            ? p.join(home, 'Memordo_Notes')
            : p.join(home, 'Documents', 'Memordo_Notes');

    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      print('📁 폴더 생성됨: $folderPath');
    } else {
      print('📁 폴더 이미 존재함: $folderPath');
    }

    return folderPath;
  }

  /// ✅ 이전 방식: 중복됨 (필요 시 유지 가능)
  Future<String> getCustomSavePath() async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];

    if (home == null) {
      throw Exception('사용자 홈 디렉터리를 찾을 수 없습니다.');
    }

    final folderPath =
        Platform.isMacOS
            ? p.join(home, 'Memordo_Notes')
            : p.join(home, 'Documents', 'Memordo_Notes');

    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      print('📁 폴더 생성됨: $folderPath');
    }

    return folderPath;
  }

  /// ✅ Markdown 파일 저장 함수 (.md 확장자 사용)
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
      );
      if (!mounted) return;
      setState(() {
        _saveStatus = "웹에서 다운로드를 시작합니다 ✅";
      });
    } else if (Platform.isMacOS || Platform.isWindows) {
      try {
        final saveDir = await getOrCreateNoteFolderPath();
        final fileName = 'note_${DateTime.now().millisecondsSinceEpoch}.md';
        final filePath = p.join(saveDir, fileName);
        final file = File(filePath);
        _lastSavedDirectoryPath = saveDir;

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

  /// ✅ 폴더 탐색기 열기 함수 (플랫폼별 실행 명령)
  Future<void> openFolderInExplorer(String folderPath) async {
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      print('❌ 폴더가 존재하지 않습니다: $folderPath');
      return;
    }

    if (Platform.isMacOS) {
      await Process.run('open', [folderPath]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [folderPath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [folderPath]);
    } else {
      print('❌ 현재 플랫폼에서는 폴더 열기 기능이 지원되지 않습니다.');
    }
  }

  /// ✅ 텍스트를 AI 백엔드로 요약 요청
  Future<void> _handleSummarizeAction() async {
    // BottomSectionController 인스턴스 가져오기
    final bottomController = Provider.of<BottomSectionController>(
      context,
      listen: false,
    );

    if (bottomController.isLoading) return;

    final textToSummarize = _textEditingController.text;

    if (textToSummarize.trim().isEmpty) {
      bottomController.updateSummary('요약할 내용이 없습니다.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('요약할 내용을 먼저 입력해주세요.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (!mounted) return;
    bottomController.setIsLoading(true); // 로딩 상태 시작
    bottomController.updateSummary(''); // 기존 요약 내용 초기화

    String? summary;
    try {
      summary = await callBackendTask(
        taskType: "summarize",
        text: textToSummarize,
      );
    } catch (e) {
      print('❌ 요약 API 호출 중 예외 발생: $e');
      summary = '요약 중 오류가 발생했습니다: $e';
    } finally {
      if (!mounted) return;
      bottomController.updateSummary(summary ?? '요약에 실패했거나 내용이 없습니다.');
      bottomController.setIsLoading(false); // 로딩 상태 종료
    }

    if (summary == null || summary.contains("오류") || summary.contains("실패")) {
      print('❌ 요약 실패 또는 오류 수신: $summary');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(summary ?? '텍스트 요약에 실패했습니다.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// ✅ UI 정의
  @override
  Widget build(BuildContext context) {
    // BottomSectionController 인스턴스 가져오기 (listen: true로 변화 감지)
    final bottomController = Provider.of<BottomSectionController>(context);

    return LeftSidebarLayout(
      activePage: PageType.home,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 40,
            color: Colors.grey[300],
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              '메인 화면 - 새 메모 작성',
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
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: '여기에 글을 작성하세요...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
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
                      const SizedBox(width: 8),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('폴더 열기'),
                        onPressed: () async {
                          try {
                            final path = await getOrCreateNoteFolderPath();
                            await openFolderInExplorer(path);
                          } catch (e) {
                            print('❌ 폴더 열기 실패: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('폴더 열기에 실패했습니다: $e')),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[700],
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),

                      Expanded(
                        child: Text(
                          _saveStatus,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            overflow: TextOverflow.ellipsis,
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
            // key는 더 이상 필요 없습니다.
            onSummarizePressed:
                bottomController.isLoading ? null : _handleSummarizeAction,
          ),
        ],
      ),
    );
  }
}
