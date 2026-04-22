import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppNotification {
  final String title;
  final String body;
  final DateTime receivedAt;
  bool isRead;

  AppNotification({
    required this.title,
    required this.body,
    required this.receivedAt,
    this.isRead = false,
  });
}

class NotificationNotifier extends StateNotifier<List<AppNotification>> {
  NotificationNotifier() : super([]);

  void add(String title, String body) {
    state = [
      AppNotification(
        title: title,
        body: body,
        receivedAt: DateTime.now(),
      ),
      ...state,
    ];
  }

  void markAllRead() {
    state = state.map((n) {
      n.isRead = true;
      return n;
    }).toList();
  }

  int get unreadCount => state.where((n) => !n.isRead).length;
}

final notificationStoreProvider =
    StateNotifierProvider<NotificationNotifier, List<AppNotification>>(
        (_) => NotificationNotifier());
