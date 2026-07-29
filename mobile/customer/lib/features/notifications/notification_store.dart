import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppNotification {
  final String title;
  final String body;
  final DateTime receivedAt;
  final String? orderId; // for deep-linking to order tracking
  final String? type; // e.g. 'order_accepted', 'order_cancelled'
  bool isRead;

  AppNotification({
    required this.title,
    required this.body,
    required this.receivedAt,
    this.orderId,
    this.type,
    this.isRead = false,
  });
}

class NotificationNotifier extends StateNotifier<List<AppNotification>> {
  NotificationNotifier() : super([]);

  void add(String title, String body, {String? orderId, String? type}) {
    state = [
      AppNotification(
        title: title,
        body: body,
        receivedAt: DateTime.now(),
        orderId: orderId,
        type: type,
        isRead: false,
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

  void markOneRead(int index) {
    final updated = [...state];
    updated[index].isRead = true;
    state = updated;
  }

  void clearAll() => state = [];

  int get unreadCount => state.where((n) => !n.isRead).length;
}

final notificationStoreProvider =
    StateNotifierProvider<NotificationNotifier, List<AppNotification>>(
        (_) => NotificationNotifier());
