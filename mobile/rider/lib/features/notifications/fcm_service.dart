import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  // Background handler — FCM shows the notification automatically
  // When user taps it, onMessageOpenedApp fires in the foreground
}

// Global callback — set by RiderHomeScreen to handle delivery requests
typedef DeliveryRequestCallback = void Function(Map<String, dynamic> data);
DeliveryRequestCallback? onDeliveryRequestReceived;

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

    // App in foreground — show snackbar or trigger delivery card
    FirebaseMessaging.onMessage.listen((message) {
      _handleMessage(message, context);
    });

    // App opened from background via notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleMessage(message, context);
    });

    // App launched from terminated state via notification tap
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleMessage(initial, context);
  }

  void _handleMessage(RemoteMessage message, BuildContext context) {
    final data = message.data;
    if (data['type'] == 'delivery_request') {
      // Trigger the delivery request card in RiderHomeScreen
      onDeliveryRequestReceived?.call(data);
    } else if (context.mounted && message.notification != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.notification!.body ?? ''),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _client.dio.post(ApiConstants.fcmToken,
          data: {'token': token, 'deviceType': 'android'});
    } catch (_) {}
  }
}
