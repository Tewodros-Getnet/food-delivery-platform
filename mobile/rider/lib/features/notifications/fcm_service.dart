import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  // Background handler — FCM shows the notification automatically
}

// Global callback — set by RiderHomeScreen to handle delivery requests
typedef DeliveryRequestCallback = void Function(Map<String, dynamic> data);
DeliveryRequestCallback? onDeliveryRequestReceived;

// Holds a delivery request that arrived before RiderHomeScreen was mounted
Map<String, dynamic>? pendingDeliveryRequest;

void storePendingDeliveryRequest(Map<String, dynamic> data) {
  if (onDeliveryRequestReceived != null) {
    onDeliveryRequestReceived!.call(data);
  } else {
    pendingDeliveryRequest = data;
  }
}

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
      _handleMessage(message, context);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleMessage(message, context);
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleMessage(initial, context);
  }

  Future<void> _handleMessage(
      RemoteMessage message, BuildContext context) async {
    final data = message.data;
    if (data['type'] == 'delivery_request') {
      final orderId = data['orderId'] as String?;
      if (orderId == null) return;
      // FCM only carries orderId — fetch full details from backend
      try {
        final res = await _client.dio
            .get('${ApiConstants.deliveries}/$orderId/details');
        final details = res.data['data'] as Map<String, dynamic>;
        storePendingDeliveryRequest(details);
      } catch (_) {
        // Fallback: pass what we have — Socket.io event will fill in the rest
        storePendingDeliveryRequest(
            {'orderId': orderId, 'expiresAt': data['expiresAt']});
      }
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
