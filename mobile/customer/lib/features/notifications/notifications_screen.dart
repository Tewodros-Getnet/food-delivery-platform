import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'notification_store.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationStoreProvider);

    // Mark all as read when screen opens
    ref.listen(notificationStoreProvider, (_, __) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationStoreProvider.notifier).markAllRead();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: notifications.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No notifications yet',
                      style: TextStyle(color: Colors.grey, fontSize: 15)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: notifications.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (ctx, i) {
                final n = notifications[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        n.isRead ? Colors.grey[100] : Colors.orange.shade50,
                    child: Icon(
                      Icons.notifications,
                      color: n.isRead ? Colors.grey : Colors.orange,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    n.title.isNotEmpty ? n.title : 'Notification',
                    style: TextStyle(
                      fontWeight:
                          n.isRead ? FontWeight.normal : FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (n.body.isNotEmpty)
                        Text(n.body, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        _timeAgo(n.receivedAt),
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                    ],
                  ),
                  isThreeLine: n.body.isNotEmpty,
                );
              },
            ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
