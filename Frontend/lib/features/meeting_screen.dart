// lib/features/meeting_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../layout/bottom_section.dart';
import '../layout/left_sidebar_layout.dart';
import '../utils/web_helper.dart';
import '../utils/ai_service.dart';
import '../layout/bottom_section_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_token.dart';
import '../providers/token_status_provider.dart';

// 오른쪽 패널에 표시될 메모 정보를 담는 클래스
class LocalMemo {
  final String fileName;
  final String filePath;
  // String? lastModified; // 필요시 마지막 수정일 추가

  LocalMemo({required this.fileName, required this.filePath});
}

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final TextEditingController _textEditingController = TextEditingController();
  String _saveStatus = '';
  String? _lastSavedDirectoryPath;

  // --- 오른쪽 메모 목록 패널 관련 상태 ---
  bool _isMemoListVisible = false;
  List<LocalMemo> _savedMemosList = [];
  bool _isLoadingMemos = false;
  // --- ---

  @override
  void initState() {
    super.initState();
    // 앱 시작 시 또는 필요에 따라 초기 메모 스캔
    // _scanForMemos(); // initState에서 호출하면 초기 로딩 가능
    _checkStoredTokens();
  }

  Future<void> _checkStoredTokens() async {
    final accessToken = await getStoredAccessToken();
    final refreshToken = await getStoredRefreshToken();

    if (accessToken != null && accessToken.isNotEmpty) {
      print('✅ 저장된 accessToken: ${accessToken.substring(0, 10)}...');
    } else {
      print('❌ accessToken 없음');
    }

    if (refreshToken != null && refreshToken.isNotEmpty) {
      print('🌀 저장된 refreshToken: ${refreshToken.substring(0, 10)}...');
    } else {
      print('❌ refreshToken 없음');
    }
  }

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
      // print('📁 폴더 이미 존재함: $folderPath');
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
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        String? initialDirectory =
            _lastSavedDirectoryPath ?? await getOrCreateNoteFolderPath();

        String? filePath = await FilePicker.platform.saveFile(
          dialogTitle: '노트 저장',
          fileName:
              '새_노트_${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}.md',
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: ['md'],
        );

        if (filePath != null) {
          final file = File(filePath);
          await file.writeAsString(content);
          _lastSavedDirectoryPath = p.dirname(filePath);
          if (!mounted) return;
          setState(() {
            _saveStatus = "저장 완료: $filePath";
          });
          // 저장 후 메모 목록 갱신 (오른쪽 패널이 열려있다면)
          if (_isMemoListVisible) {
            _scanForMemos();
          }
        } else {
          if (!mounted) return;
          setState(() {
            _saveStatus = "파일 저장이 취소되었습니다.";
          });
        }
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

  /// ✅ Markdown 파일 불러오기 함수
  Future<void> _loadMarkdown() async {
    String? content;
    String? fileName;

    if (kIsWeb) {
      content = await pickFileWeb();
      if (content != null) {
        fileName = '불러온 파일 (웹)';
      }
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['md', 'txt'],
        );

        if (result != null && result.files.single.path != null) {
          File file = File(result.files.single.path!);
          content = await file.readAsString();
          fileName = p.basename(file.path);
          _lastSavedDirectoryPath = p.dirname(file.path); // 불러온 파일의 디렉토리도 기억
        } else {
          if (!mounted) return;
          setState(() {
            _saveStatus = "파일 선택이 취소되었습니다.";
          });
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _saveStatus = "파일 불러오기 오류 ❌: $e";
        });
        print('Error loading file: $e');
        return;
      }
    } else {
      if (!mounted) return;
      setState(() {
        _saveStatus =
            "${Platform.operatingSystem} 플랫폼은 아직 파일 불러오기 기능이 지원되지 않습니다 🛑";
      });
      return;
    }

    if (content != null && mounted) {
      setState(() {
        _textEditingController.text = content!;
        _saveStatus = "파일 불러오기 완료: ${fileName ?? '알 수 없는 파일'} ✅";
      });
    } else if (mounted) {
      setState(() {
        _saveStatus = "파일을 불러오지 못했거나 내용이 없습니다.";
      });
    }
  }

  /// ✅ 폴더 탐색기 열기 함수
  Future<void> openFolderInExplorer(String folderPath) async {
    // ... (기존 코드와 동일) ...
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      print('❌ 폴더가 존재하지 않습니다: $folderPath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("지정된 폴더를 찾을 수 없습니다: $folderPath")),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("현재 플랫폼에서는 폴더 열기 기능이 지원되지 않습니다.")),
        );
      }
    }
  }

  /// ✅ 텍스트를 AI 백엔드로 요약 요청
  Future<void> _handleSummarizeAction() async {
    // ... (기존 코드와 동일, 에러 메시지 등 개선 가능) ...
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
    bottomController.setIsLoading(true);
    bottomController.updateSummary('');

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
      bottomController.setIsLoading(false);
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

  // --- 오른쪽 메모 목록 패널 관련 메소드 ---
  void _toggleMemoListVisibility() {
    setState(() {
      _isMemoListVisible = !_isMemoListVisible;
    });
    // 패널이 열릴 때 메모 스캔 (웹 환경 제외)
    if (_isMemoListVisible && !kIsWeb) {
      _scanForMemos();
    }
  }

  Future<void> _scanForMemos() async {
    if (!mounted) return;
    setState(() {
      _isLoadingMemos = true;
      _savedMemosList = [];
    });

    try {
      final notesDir = await getOrCreateNoteFolderPath();
      final directory = Directory(notesDir);
      if (await directory.exists()) {
        final List<LocalMemo> memos = [];
        await for (var entity in directory.list().handleError((error) {
          print("Error listing directory: $error");
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('메모 폴더 접근 중 오류: $error')));
          }
        })) {
          if (entity is File &&
              p.extension(entity.path).toLowerCase() == '.md') {
            memos.add(
              LocalMemo(
                fileName: p.basenameWithoutExtension(
                  entity.path,
                ), // 확장자 제외한 파일명
                filePath: entity.path,
              ),
            );
          }
        }
        if (mounted) {
          // 파일 이름순으로 정렬 (선택 사항)
          memos.sort((a, b) => a.fileName.compareTo(b.fileName));
          setState(() {
            _savedMemosList = memos;
          });
        }
      }
    } catch (e) {
      print('Error scanning memos: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('메모 목록을 불러오는 중 오류 발생: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMemos = false;
        });
      }
    }
  }

  Future<void> _loadSelectedMemo(LocalMemo memo) async {
    try {
      final file = File(memo.filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (mounted) {
          setState(() {
            _textEditingController.text = content;
            _saveStatus = "파일 불러오기 완료: ${memo.fileName}.md ✅";
            _isMemoListVisible = false; // 선택 후 패널 닫기
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _saveStatus = "파일을 찾을 수 없습니다: ${memo.fileName}.md";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('파일을 찾을 수 없습니다: ${memo.fileName}.md')),
          );
        }
      }
    } catch (e) {
      print('Error loading selected memo: $e');
      if (mounted) {
        setState(() {
          _saveStatus = "파일 읽기 오류: $e";
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('메모를 불러오는 중 오류 발생: $e')));
      }
    }
  }

  Widget _buildMemoListPanel() {
    return Material(
      // Material 위젯으로 감싸서 Theming 적용 및 시각적 개선
      elevation: 4.0, // 패널에 그림자 효과
      child: Container(
        width: 280,
        color: Theme.of(context).canvasColor, // 테마의 캔버스 색 사용
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "저장된 메모",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: "새로고침",
                        onPressed: _isLoadingMemos ? null : _scanForMemos,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: "닫기",
                        onPressed: _toggleMemoListVisibility,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            if (_isLoadingMemos)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_savedMemosList.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "저장된 메모가 없습니다.\n'.md 파일로 저장' 기능을 사용해보세요.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _savedMemosList.length,
                  separatorBuilder:
                      (context, index) => Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: Theme.of(context).dividerColor.withOpacity(0.5),
                      ),
                  itemBuilder: (context, index) {
                    final memo = _savedMemosList[index];
                    return ListTile(
                      title: Text(
                        memo.fileName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      // subtitle: Text(memo.filePath, maxLines: 1, overflow: TextOverflow.ellipsis), // 필요시 경로 표시
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 0,
                      ),
                      dense: true,
                      onTap: () => _loadSelectedMemo(memo),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
  // --- ---

  /// ✅ UI 정의
  @override
  Widget build(BuildContext context) {
    final bottomController = Provider.of<BottomSectionController>(context);

    // 메인 콘텐츠 영역을 별도 위젯이나 메소드로 분리하면 가독성이 좋아집니다.
    Widget mainContentArea = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 48,
          // color: Colors.grey[100], // 기존 색상 또는 테마 색상 사용
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color:
                Theme.of(context).appBarTheme.backgroundColor ??
                Colors.grey[100], // 테마 AppBar 배경색 또는 기본값
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '메인 화면 - 새 메모 작성',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              if (!kIsWeb) // 웹에서는 파일 시스템 접근이 다르므로 일단 숨김
                IconButton(
                  icon: Icon(
                    _isMemoListVisible ? Icons.menu_open : Icons.menu,
                    color:
                        Theme.of(context).iconTheme.color ??
                        Colors.deepPurple.shade400,
                  ),
                  tooltip: "저장된 메모 목록 보기/숨기기",
                  onPressed: _toggleMemoListVisibility,
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              0,
            ), // 하단 패딩은 CollapsibleBottomSection 전까지
            child: Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textEditingController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText: '여기에 글을 작성하세요...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide(color: Colors.grey.shade400),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    style: const TextStyle(fontSize: 16, height: 1.6),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: const Icon(
                        Icons.file_upload_outlined,
                        size: 18,
                      ), // 아이콘 변경
                      label: const Text('노트 불러오기'),
                      onPressed: _loadMarkdown,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: const Icon(
                        Icons.snippet_folder_outlined,
                        size: 18,
                      ), // 아이콘 변경
                      label: const Text('저장 폴더 열기'),
                      onPressed: () async {
                        if (kIsWeb) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("웹 환경에서는 폴더 열기를 지원하지 않습니다."),
                            ),
                          );
                          return;
                        }
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _saveStatus,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).hintColor,
                          overflow: TextOverflow.ellipsis,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12), // CollapsibleBottomSection 전 간격
              ],
            ),
          ),
        ),
        CollapsibleBottomSection(
          onSummarizePressed:
              bottomController.isLoading ? null : _handleSummarizeAction,
        ),
      ],
    );

    return LeftSidebarLayout(
      activePage: PageType.home,
      child: Row(
        // 메인 콘텐츠와 오른쪽 패널을 Row로 배치
        children: [
          Expanded(
            child: mainContentArea, // 기존 메인 콘텐츠
          ),
          if (_isMemoListVisible && !kIsWeb)
            _buildMemoListPanel(), // 조건부로 오른쪽 패널 표시 (웹 제외)
        ],
      ),
    );
  }
}
