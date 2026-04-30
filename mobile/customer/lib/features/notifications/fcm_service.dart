import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_constants.dart';
import 'notification_store.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {}

final fcmServiceProvider =
    Provider<FcmService>((ref) => FcmService(ref.read(dioClientProvider), ref));

class FcmService {
  final DioClient _client;
  final Ref _ref;
  FcmService(this._client, this._ref);

  Future<void> initialize(BuildContext context) async {
    FirebaseMessaging.onBackgroundMessage(_bgHandler);

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);
    }

    // Foreground notifications — show snackbar AND store
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? '';
      final body = message.notification?.body ?? '';
      if (title.isNotEmpty || body.isNotEmpty) {
        _ref.read(notificationStoreProvider.notifier).add(title, body);
      }
      if (context.mounted && body.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(body),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });

    // Notification tapped while app in background — deep-link route
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final title = message.notification?.title ?? '';
      final body = message.notification?.body ?? '';
      if (title.isNotEmpty || body.isNotEmpty) {
        _ref.read(notificationStoreProvider.notifier).add(title, body);
      }
      if (context.mounted) _handleDeepLink(context, message.data);
    });

    // Notification that launched the app from terminated state — deep-link route
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final title = initial.notification?.title ?? '';
      final body = initial.notification?.body ?? '';
      if (title.isNotEmpty || body.isNotEmpty) {
        _ref.read(notificationStoreProvider.notifier).add(title, body);
      }
      // Defer until the widget tree is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _handleDeepLink(context, initial.data);
      });
    }
  }

  /// Routes the user to the relevant screen based on the notification payload.
  void _handleDeepLink(BuildContext context, Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final orderId = data['orderId'] as String?;

    switch (type) {
      case 'order_accepted':
      case 'order_rejected':
      case 'order_cancelled':
      case 'order_status_update':
        if (orderId != null) {
          context.push('/order/$orderId/track');
        }
        break;
      case 'delivery_request':
        // Customers don't receive delivery requests — ignore
        break;
      default:
        // Unknown type — navigate to orders list
        context.go('/orders');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _client.dio.post(ApiConstants.fcmToken,
          data: {'token': token, 'deviceType': 'android'});
    } catch (_) {}
  }
}
