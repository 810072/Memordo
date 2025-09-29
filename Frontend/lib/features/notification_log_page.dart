import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/status_bar_provider.dart';

class NotificationLogPage extends StatelessWidget {
  const NotificationLogPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 페이지에 들어오면 알림을 '읽음'으로 처리
    context.read<StatusBarProvider>().markAsRead();

    return Scaffold(
      appBar: AppBar(title: const Text('알림')),
      body: Consumer<StatusBarProvider>(
        builder: (context, provider, child) {
          if (provider.logs.isEmpty) {
            return const Center(
              child: Text(
                '표시할 알림이 없습니다.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return ListView.builder(
            itemCount: provider.logs.length,
            itemBuilder: (context, index) {
              final log = provider.logs[index];
              return _buildLogTile(context, log);
            },
          );
        },
      ),
    );
  }

  Widget _buildLogTile(BuildContext context, NotificationLog log) {
    IconData iconData;
    Color iconColor;
    final theme = Theme.of(context);

    switch (log.type) {
      case StatusType.success:
        iconData = Icons.check_circle_outline;
        iconColor = theme.textTheme.bodyMedium?.color ?? Colors.black;
        break;
      case StatusType.error:
        iconData = Icons.error_outline;
        iconColor = Colors.redAccent.shade700;
        break;
      case StatusType.info:
      default:
        iconData = Icons.info_outline;
        iconColor = Colors.grey.shade600;
        break;
    }

    return ListTile(
      leading: Icon(iconData, color: iconColor),
      title: Text(log.message, style: TextStyle(color: iconColor)),
      subtitle: Text(
        DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp),
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      ),
      dense: true,
    );
  }
}
