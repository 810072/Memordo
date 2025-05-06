// meeting_screen.dart
import 'dart:io' show File, Directory, Platform; // 파일 및 디렉토리 관련 기능 임포트
import 'package:flutter/foundation.dart' show kIsWeb; // 웹 환경인지 확인하는 기능 임포트
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p; // 경로 조작 라이브러리 임포트

import 'left_sidebar_layout.dart'; // 좌측 사이드바 레이아웃 임포트 (여기서는 사용하지 않음)
import 'bottom_section.dart'; // 하단 액션 영역 위젯 임포트
import 'utils/web_helper.dart'; // 웹 환경 도우미 함수 임포트

// 미팅 화면 위젯 (메인 화면 역할)
// 이 위젯은 LeftSidebarLayout의 child로 사용될 예정이므로 내부에서 LeftSidebarLayout을 사용하지 않습니다.
class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

// MeetingScreen 위젯의 상태를 관리하는 클래스
class _MeetingScreenState extends State<MeetingScreen> {
  // 텍스트 입력 필드를 제어하는 컨트롤러
  final TextEditingController _controller = TextEditingController();
  // 작업 상태 메시지를 저장하는 변수
  String _status = '';

  /// ✅ Markdown 파일 저장 경로 설정 (macOS 기준 예시)
  Future<String> getCustomSavePath() async {
    // 사용자 홈 디렉토리 경로 가져오기
    final home = Platform.environment['HOME'] ?? '/Users/unknown_user';
    // 저장할 폴더 경로 설정
    final folderPath = '$home/Memo'; // 완전히 명시적인 경로 사용
    final directory = Directory(folderPath); // 디렉토리 객체 생성

    // 디렉토리가 존재하지 않으면 생성 (재귀적으로 상위 폴더까지 생성)
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return folderPath; // 생성 또는 확인된 폴더 경로 반환
  }

  // Markdown 파일을 저장하는 비동기 함수
  Future<void> _saveMarkdown() async {
    final content = _controller.text; // 텍스트 필드의 내용 가져오기

    // 현재 실행 환경 확인 (웹 또는 데스크탑/모바일)
    if (kIsWeb) {
      // 웹 환경인 경우 웹 전용 다운로드 함수 호출
      downloadMarkdownWeb(content);
      setState(() {
        _status = "웹에서 다운로드됨 ✅"; // 상태 메시지 업데이트
      });
    } else if (Platform.isMacOS) {
      // macOS 환경인 경우 로컬 파일 시스템에 저장
      try {
        final saveDir = await getCustomSavePath(); // 저장할 디렉토리 경로 가져오기
        // 파일 이름 생성 (현재 시간을 이용하여 고유하게)
        final fileName = 'note_${DateTime.now().millisecondsSinceEpoch}.md';
        // 디렉토리 경로와 파일 이름을 합쳐 전체 파일 경로 생성
        final filePath = p.join(saveDir, fileName);

        final file = File(filePath); // File 객체 생성
        await file.writeAsString(content); // 파일에 내용 쓰기 (비동기)
        setState(() {
          _status = "저장 완료: $filePath"; // 상태 메시지 업데이트 (성공)
        });
      } catch (e) {
        // 저장 중 오류 발생 시
        setState(() {
          _status = "오류 발생 ❌: $e"; // 상태 메시지 업데이트 (오류)
        });
      }
    } else {
      // 지원되지 않는 플랫폼인 경우
      setState(() {
        _status = "이 플랫폼은 아직 지원되지 않아요 🛑"; // 상태 메시지 업데이트
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // LeftSidebarLayout을 사용하지 않고, 메인 콘텐츠 부분만 반환합니다.
    return Column(
      // 메인 콘텐츠 영역 구성 (MeetingScreen의 내용)
      crossAxisAlignment: CrossAxisAlignment.start, // 자식 위젯을 왼쪽으로 정렬
      children: [
        // 상단 바: 페이지 제목 표시
        Container(
          height: 50,
          color: Colors.grey[300], // 배경색
          alignment: Alignment.centerLeft, // 내용을 왼쪽으로 정렬
          padding: const EdgeInsets.symmetric(horizontal: 16), // 좌우 여백
          child: const Text(
            '메인 화면', // 제목 텍스트
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          // 남은 공간을 채우는 위젯
          child: Padding(
            padding: const EdgeInsets.all(16.0), // 내부 여백
            child: Column(
              // 자식 위젯을 세로로 배치
              children: [
                Expanded(
                  // 텍스트 필드가 남은 공간을 모두 사용하도록 함
                  child: TextField(
                    controller: _controller, // 텍스트 필드 제어 컨트롤러 연결
                    maxLines: null, // 자동 줄바꿈 (무제한)
                    expands: true, // 부모의 남은 공간을 채우도록 확장
                    decoration: const InputDecoration(
                      // 입력 필드 디자인
                      hintText: '여기에 글을 작성하세요...', // 힌트 텍스트
                      border: OutlineInputBorder(), // 테두리 스타일
                    ),
                  ),
                ),
                const SizedBox(height: 10), // 위젯 간 세로 간격
                Row(
                  // 자식 위젯을 가로로 배치
                  children: [
                    // '.md 파일로 저장' 버튼
                    ElevatedButton(
                      onPressed: _saveMarkdown, // 버튼 클릭 시 _saveMarkdown 함수 호출
                      child: const Text('.md 파일로 저장'), // 버튼 텍스트
                    ),
                    const SizedBox(width: 10), // 위젯 간 가로 간격
                    // 작업 상태 메시지를 표시하는 텍스트 영역
                    Flexible(
                      // 텍스트가 너무 길 경우 줄바꿈되도록 유연하게 공간 할당
                      child: Text(
                        _status, // 상태 메시지
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // 하단에 Collapse 가능한 액션 영역 위젯 추가
        const CollapsibleBottomSection(),
      ],
    );
  }
}
