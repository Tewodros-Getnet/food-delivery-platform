import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'notification_store.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationStoreProvider);
    final unread = notifications.where((n) => !n.isRead).length;

    // Mark all as read when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationStoreProvider.notifier).markAllRead();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (notifications.isNotEmpty)
            TextButton(
              onPressed: () =>
                  ref.read(notificationStoreProvider.notifier).clearAll(),
              child: const Text('Clear all',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ],
      ),
      body: notifications.isEmpty
          ? _buildEmpty()
          : _buildList(context, ref, notifications, unread),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 72, color: Colors.grey),
          SizedBox(height: 16),
          Text('No notifications yet',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: 6),
          Text('Order updates will appear here',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref,
      List<AppNotification> notifications, int unread) {
    // Group by date: Today / Yesterday / Earlier
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayItems =
        notifications.where((n) => n.receivedAt.isAfter(today)).toList();
    final yesterdayItems = notifications
        .where((n) =>
            n.receivedAt.isAfter(yesterday) && !n.receivedAt.isAfter(today))
        .toList();
    final earlierItems =
        notifications.where((n) => !n.receivedAt.isAfter(yesterday)).toList();

    return ListView(
      children: [
        if (unread > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, color: Colors.orange, size: 8),
                const SizedBox(width: 8),
                Text(
                  '$unread unread notification${unread > 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => ref
                      .read(notificationStoreProvider.notifier)
                      .markAllRead(),
                  child: const Text('Mark all read',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
        if (todayItems.isNotEmpty) ...[
          _GroupHeader('Today'),
          ...todayItems.map((n) => _NotificationTile(
                notification: n,
                index: notifications.indexOf(n),
              )),
        ],
        if (yesterdayItems.isNotEmpty) ...[
          _GroupHeader('Yesterday'),
          ...yesterdayItems.map((n) => _NotificationTile(
                notification: n,
                index: notifications.indexOf(n),
              )),
        ],
        if (earlierItems.isNotEmpty) ...[
          _GroupHeader('Earlier'),
          ...earlierItems.map((n) => _NotificationTile(
                notification: n,
                index: notifications.indexOf(n),
              )),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  final int index;

  const _NotificationTile({
    required this.notification,
    required this.index,
  });

  IconData _iconFor(String? type) {
    switch (type) {
      case 'order_accepted':
        return Icons.check_circle_outline;
      case 'order_rejected':
      case 'order_cancelled':
        return Icons.cancel_outlined;
      case 'order_status_update':
        return Icons.local_shipping_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String? type) {
    switch (type) {
      case 'order_accepted':
        return Colors.green;
      case 'order_rejected':
      case 'order_cancelled':
        return Colors.red;
      case 'order_status_update':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final color = _colorFor(n.type);
    final hasLink = n.orderId != null;

    return InkWell(
      onTap: hasLink
          ? () {
              ref.read(notificationStoreProvider.notifier).markOneRead(index);
              context.push('/order/${n.orderId}/track');
            }
          : null,
      child: Container(
        color: n.isRead ? null : Colors.orange.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_iconFor(n.type), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title.isNotEmpty ? n.title : 'Notification',
                            style: TextStyle(
                              fontWeight: n.isRead
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (!n.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (n.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        n.body,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _timeAgo(n.receivedAt),
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 11),
                        ),
                        if (hasLink) ...[
                          const SizedBox(width: 8),
                          Text(
                            'View order →',
                            style: TextStyle(
                              color: Colors.orange[700],
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
