import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {}

// Global callback — set by OrdersScreen to reload orders when a notification is tapped
typedef OrdersReloadCallback = void Function();
OrdersReloadCallback? onOrdersReloadRequested;

final fcmServiceProvider =
    Provider<FcmService>((ref) => FcmService(ref.read(dioClientProvider)));

class FcmService {
  final DioClient _client;
  FcmService(this._client);

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
    FirebaseMessaging.onMessage.listen((message) {
      if (context.mounted && message.notification != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.notification!.body ?? ''),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // Reload orders list when a new order notification arrives in foreground
      onOrdersReloadRequested?.call();
    });

    // App opened from background by tapping notification — reload orders
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onOrdersReloadRequested?.call();
    });

    // App launched from terminated state by tapping notification — reload orders
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onOrdersReloadRequested?.call();
      });
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _client.dio.post(ApiConstants.fcmToken,
          data: {'token': token, 'deviceType': 'android'});
    } catch (_) {}
  }
}
