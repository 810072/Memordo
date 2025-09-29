import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/status_bar_provider.dart';

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
                _buildNotificationBell(context),
              ],
            ),
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
              clipBehavior: Clip.none, // ✨ [추가] 점이 잘리지 않도록 함
              children: [
                Icon(
                  Icons.notifications_none_outlined,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                if (provider.hasUnread)
                  Positioned(
                    top: 2, // ✨ [수정] 위치 미세 조정
                    right: 3, // ✨ [수정] 위치 미세 조정
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
