// lib/model/file_system_entry.dart
class FileSystemEntry {
  final String name; // 파일/폴더 이름
  final String path; // 절대 경로
  final bool isDirectory; // 폴더인지 여부
  final List<FileSystemEntry>? children; // 폴더인 경우 자식 목록
  bool isPinned; // ✨ [추가] 고정 상태를 나타내는 플래그

  FileSystemEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children,
    this.isPinned = false, // 기본값은 false
  });

  // 선택 사항: JSON 직렬화/역직렬화 메서드 (필요시 추가)
  // factory FileSystemEntry.fromJson(Map<String, dynamic> json) { ... }
  // Map<String, dynamic> toJson() { ... }
}
