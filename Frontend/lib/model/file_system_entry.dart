// lib/model/file_system_entry.dart
class FileSystemEntry {
  final String name; // 파일/폴더 이름
  final String path; // 절대 경로
  final bool isDirectory; // 폴더인지 여부
  final List<FileSystemEntry>? children; // 폴더인 경우 자식 목록
  bool isPinned; // 고정 상태를 나타내는 플래그
  final DateTime? modifiedTime; // ✨ [추가] 파일의 최종 수정 시간

  FileSystemEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children,
    this.isPinned = false,
    this.modifiedTime, // ✨ [추가]
  });
}
