// lib/widgets/status_bar_widget.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/status_bar_provider.dart';
import '../providers/note_provider.dart'; // ✨ [추가] NoteProvider 임포트

class StatusBarWidget extends StatelessWidget {
  final VoidCallback onBellPressed;

  const StatusBarWidget({Key? key, required this.onBellPressed})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<StatusBarProvider>(
      builder: (context, provider, child) {
        final theme = Theme.of(context);

        Color iconAndTextColor;
        IconData iconData;
        String message;

        if (provider.isVisible) {
          message = provider.message;

          switch (provider.type) {
            case StatusType.success:
              iconAndTextColor =
                  theme.textTheme.bodyMedium?.color ?? Colors.black;
              iconData = Icons.check_circle_outline;
              break;
            case StatusType.error:
              iconAndTextColor = Colors.redAccent.shade700;
              iconData = Icons.error_outline;
              break;
            case StatusType.info:
            default:
              iconAndTextColor =
                  theme.textTheme.bodyMedium?.color ?? Colors.grey.shade800;
              iconData = Icons.info_outline;
              break;
          }
        } else {
          iconAndTextColor = Colors.grey.shade600;
          iconData = Icons.check_outlined;
          message = '준비';
        }

        return Material(
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(
                top: BorderSide(color: theme.dividerColor, width: 1.0),
              ),
            ),
            padding: const EdgeInsets.only(left: 16.0),
            child: Row(
              children: [
                Icon(iconData, color: iconAndTextColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: iconAndTextColor, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildTextInfo(context), // ✨ [수정] 위젯 호출
                _buildNotificationBell(context),
              ],
            ),
          ),
        );
      },
    );
  }

  // ✨ [수정] 텍스트 정보 표시 위젯 수정
  Widget _buildTextInfo(BuildContext context) {
    // NoteProvider의 상태를 직접 구독하여 최신 정보를 표시
    return Consumer<NoteProvider>(
      builder: (context, noteProvider, child) {
        // 표시할 정보가 없으면 (열린 노트가 없으면) 빈 컨테이너 반환
        if (noteProvider.controller == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            '현재 줄: ${noteProvider.currentLine}, 글자 수: ${noteProvider.totalLineChars} / 전체: ${noteProvider.totalChars}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        );
      },
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    return Consumer<StatusBarProvider>(
      builder: (context, provider, child) {
        return SizedBox(
          width: 40,
          height: 24,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.notifications_none_outlined,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                if (provider.hasUnread)
                  Positioned(
                    top: 2,
                    right: 3,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade400,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).cardColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: onBellPressed,
            splashRadius: 18,
            tooltip: '알림 로그 보기',
          ),
        );
      },
    );
  }
}
