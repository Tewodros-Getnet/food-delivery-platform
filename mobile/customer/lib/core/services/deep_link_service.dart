import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  /// Initialize deep link listening
  Future<void> initialize(BuildContext context) async {
    try {
      // Handle initial link when app is opened from terminated state
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null && context.mounted) {
        _handleDeepLink(context, initialUri);
      }

      // Handle deep links when app is already running
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (Uri uri) {
          if (context.mounted) {
            _handleDeepLink(context, uri);
          }
        },
        onError: (err) {
          debugPrint('Deep link error: $err');
        },
      );
    } catch (e) {
      debugPrint('Failed to initialize deep links: $e');
    }
  }

  /// Handle incoming deep link
  void _handleDeepLink(BuildContext context, Uri uri) {
    debugPrint('Received deep link: $uri');
    
    try {
      // Expected format: fooddelivery://customer/reset-password?token=xyz
      // Also support legacy: fooddelivery://app/reset-password?token=xyz
      if (uri.scheme == 'fooddelivery' && 
          (uri.host == 'customer' || uri.host == 'app')) {
        final path = uri.path;
        final queryParams = uri.queryParameters;
        
        if (path == '/reset-password' && queryParams.containsKey('token')) {
          final token = queryParams['token'];
          if (token != null && token.isNotEmpty && context.mounted) {
            // Navigate to reset password screen
            GoRouter.of(context).go('/reset-password?token=$token');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to handle deep link: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _linkSubscription?.cancel();
  }
}