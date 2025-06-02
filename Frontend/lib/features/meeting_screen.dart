// lib/features/meeting_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../layout/bottom_section_controller.dart';
import '../layout/main_layout.dart'; // Import MainLayout
import '../layout/right_sidebar_content.dart'; // Import RightSidebarContent
import '../widgets/ai_summary_widget.dart'; // Import AiSummaryWidget
import '../utils/web_helper.dart';
import '../utils/ai_service.dart';
import '../layout/ai_summary_controller.dart'; // Import (renamed) AiSummaryController
import 'page_type.dart';

class LocalMemo {
  final String fileName;
  final String filePath;
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
  List<LocalMemo> _savedMemosList = [];
  bool _isLoadingMemos = false;

  @override
  void initState() {
    super.initState();
    _scanForMemos(); // Load memos on init

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final aiController = Provider.of<BottomSectionController>(
        context,
        listen: false,
      );
      aiController.clearSummary();
    });
  }

  // ... (getOrCreateNoteFolderPath, _saveMarkdown, _loadMarkdown, openFolderInExplorer functions remain largely the same) ...
  // --- Make sure to keep these functions ---
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

  Future<void> _saveMarkdown() async {
    final content = _textEditingController.text;
    if (content.isEmpty) {
      /* ... */
      return;
    }
    if (kIsWeb) {
      /* ... */
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
          _scanForMemos(); // Refresh list after saving
        } else {
          if (!mounted) return;
          setState(() {
            _saveStatus = "파일 저장이 취소되었습니다.";
          });
        }
      } catch (e) {
        /* ... */
      }
    } else {
      /* ... */
    }
  }

  Future<void> _loadMarkdown() async {
    String? content;
    String? fileName;
    if (kIsWeb) {
      /* ... */
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
          _lastSavedDirectoryPath = p.dirname(file.path);
        } else {
          /* ... */
          return;
        }
      } catch (e) {
        /* ... */
        return;
      }
    } else {
      /* ... */
      return;
    }
    if (content != null && mounted) {
      setState(() {
        _textEditingController.text = content!;
        _saveStatus = "파일 불러오기 완료: ${fileName ?? '알 수 없는 파일'} ✅";
      });
    } else if (mounted) {
      /* ... */
    }
  }
  // --- End of existing functions to keep ---

  Future<void> _handleSummarizeAction() async {
    final aiController = Provider.of<BottomSectionController>(
      context,
      listen: false,
    );
    if (aiController.isLoading) return;

    final textToSummarize = _textEditingController.text;
    if (textToSummarize.trim().isEmpty) {
      aiController.updateSummary('요약할 내용이 없습니다.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '여기에 사용자에게 전달할 메시지를 입력하세요.', // 예: "저장할 내용이 없습니다." 또는 "요약에 실패했습니다." 등
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor:
              Colors
                  .orangeAccent, // 메시지 종류에 따라 Colors.redAccent, Colors.green, Color(0xFF3d98f4) 등 사용
          behavior: SnackBarBehavior.floating, // 화면 하단에 떠 있는 형태로 표시
          shape: RoundedRectangleBorder(
            // 모서리를 둥글게
            borderRadius: BorderRadius.circular(10.0),
          ),
          margin: EdgeInsets.only(
            // 화면 가장자리와 여백
            bottom:
                MediaQuery.of(context).size.height - 100, // 화면 상단 근처에 표시 (예시)
            right: 20,
            left: 20,
          ),
          duration: Duration(seconds: 3), // 표시 시간
        ),
      );
      return;
    }

    aiController.setIsLoading(true);
    aiController.updateSummary(''); // Clear previous

    String? summary;
    try {
      summary = await callBackendTask(
        taskType: "summarize",
        text: textToSummarize,
      );
    } catch (e) {
      summary = '요약 중 오류가 발생했습니다: $e';
    } finally {
      if (!mounted) return;
      aiController.updateSummary(summary ?? '요약에 실패했거나 내용이 없습니다.');
      aiController.setIsLoading(false);
    }
    if (summary == null || summary.contains("오류") || summary.contains("실패")) {
      // ... (Show SnackBar) ...
    }
  }

  Future<void> _scanForMemos() async {
    if (kIsWeb) return; // Skip for web
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
        await for (var entity in directory.list()) {
          if (entity is File &&
              p.extension(entity.path).toLowerCase() == '.md') {
            memos.add(
              LocalMemo(
                fileName: p.basenameWithoutExtension(entity.path),
                filePath: entity.path,
              ),
            );
          }
        }
        if (mounted) {
          memos.sort((a, b) => a.fileName.compareTo(b.fileName));
          setState(() {
            _savedMemosList = memos;
          });
        }
      }
    } catch (e) {
      /* ... */
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
            // Optionally close right sidebar: You'd need a way to control MainLayout's state
          });
        }
      } else {
        /* ... */
      }
    } catch (e) {
      /* ... */
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiController = Provider.of<AiSummaryController>(context);

    return MainLayout(
      // Use MainLayout as the wrapper
      activePage: PageType.home,
      rightSidebarChild:
          kIsWeb
              ? null
              : RightSidebarContent(
                // Provide the right sidebar content (except for web)
                isLoading: _isLoadingMemos,
                memos: _savedMemosList,
                onMemoTap: _loadSelectedMemo,
                onRefresh: _scanForMemos,
              ),
      child: Padding(
        // Main content area padding
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          // Allow scrolling if content overflows
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Text Area
              TextField(
                controller: _textEditingController,
                minLines: 15, // min-h-[300px] approximation
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'Write your notes here...',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0), // rounded-xl
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: const BorderSide(
                      color: Color(0xFF3d98f4),
                      width: 2.0,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(16),
                ),
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: Color(0xFF334155),
                ), // text-slate-700
              ),
              const SizedBox(height: 24), // mt-6
              // Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _buildButton(
                        icon: Icons.save_outlined,
                        label: 'Save',
                        onPressed: _saveMarkdown,
                        bgColor: const Color(0xFF3d98f4), // Blue
                      ),
                      const SizedBox(width: 12),
                      _buildButton(
                        icon: Icons.file_upload_outlined,
                        label: 'Load',
                        onPressed: _loadMarkdown,
                        bgColor: const Color(0xFFE2E8F0), // Slate-200
                        fgColor: const Color(0xFF334155), // Slate-700
                      ),
                    ],
                  ),
                  _buildButton(
                    icon: Icons.auto_awesome_outlined,
                    label: 'AI Summarize',
                    onPressed:
                        aiController.isLoading ? null : _handleSummarizeAction,
                    bgColor: const Color(0xFFF59E0B), // Amber-500
                  ),
                ],
              ),
              // AI Summary Section
              const AiSummaryWidget(),

              // Save Status (Optional)
              const SizedBox(height: 20),
              Text(
                _saveStatus,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).hintColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color bgColor,
    Color fgColor = Colors.white,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 15,
        ), // h-10 px-5
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ), // rounded-lg
        elevation: 2.0, // shadow-md
        shadowColor: Colors.black.withOpacity(0.2),
      ).copyWith(
        backgroundColor: MaterialStateProperty.resolveWith<Color?>((
          Set<MaterialState> states,
        ) {
          if (states.contains(MaterialState.disabled))
            return bgColor.withOpacity(0.6);
          return bgColor; // Use the component's default.
        }),
      ),
    );
  }
}
