import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:food_delivery_customer/features/auth/providers/auth_provider.dart';
import 'package:food_delivery_customer/features/auth/screens/otp_screen.dart';
import 'package:food_delivery_customer/features/auth/services/auth_service.dart';
import 'package:food_delivery_customer/core/network/dio_client.dart';
import 'package:food_delivery_customer/core/storage/secure_storage.dart';

// ── Fake AuthService ──────────────────────────────────────────────────────────

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(DioClient(), SecureStorageService());
  @override
  Future<bool> isLoggedIn() async => false;
  @override
  Future<void> logout() async {}
}

// ── Fake notifiers ────────────────────────────────────────────────────────────

class FakeOtpNotifier extends AuthNotifier {
  FakeOtpNotifier() : super(_FakeAuthService());
  bool verifyCalled = false;
  String? lastCode;

  @override
  Future<void> verifyOtp(String code) async {
    verifyCalled = true;
    lastCode = code;
  }

  @override
  Future<void> resendOtp() async {}
}

class FakeOtpErrorNotifier extends AuthNotifier {
  FakeOtpErrorNotifier() : super(_FakeAuthService());

  @override
  Future<void> verifyOtp(String code) async {
    state = state.copyWith(
      isLoading: false,
      error: 'Invalid verification code',
    );
  }

  @override
  Future<void> resendOtp() async {}
}

// ── Helper ────────────────────────────────────────────────────────────────────

Widget _buildOtpScreen({AuthNotifier? notifier}) {
  final router = GoRouter(
    initialLocation: '/verify-otp',
    routes: [
      GoRoute(path: '/verify-otp', builder: (_, __) => const OtpScreen()),
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('Home'))),
    ],
  );

  return ProviderScope(
    overrides:
        notifier != null ? [authProvider.overrideWith((_) => notifier)] : [],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('OtpScreen — UI structure', () {
    testWidgets('renders 6 OTP input boxes', (tester) async {
      await tester.pumpWidget(_buildOtpScreen());
      await tester.pump(); // don't settle — timer is running

      // 6 TextField widgets for OTP boxes
      expect(find.byType(TextField), findsNWidgets(6));
    });

    testWidgets('renders Check your email heading', (tester) async {
      await tester.pumpWidget(_buildOtpScreen());
      await tester.pump();

      expect(find.text('Check your email'), findsOneWidget);
    });

    testWidgets('renders Verify button', (tester) async {
      await tester.pumpWidget(_buildOtpScreen());
      await tester.pump();

      expect(find.text('Verify'), findsOneWidget);
    });

    testWidgets('Verify button is disabled when OTP is incomplete',
        (tester) async {
      await tester.pumpWidget(_buildOtpScreen());
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Verify'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows resend cooldown timer initially', (tester) async {
      await tester.pumpWidget(_buildOtpScreen());
      await tester.pump();

      // Should show countdown (60s initially)
      expect(find.textContaining('Resend code in'), findsOneWidget);
    });
  });

  group('OtpScreen — interactions', () {
    testWidgets('Verify button enabled after entering 6 digits',
        (tester) async {
      final notifier = FakeOtpNotifier();
      await tester.pumpWidget(_buildOtpScreen(notifier: notifier));
      await tester.pump();

      // Enter one digit in each box
      final textFields = find.byType(TextField);
      for (int i = 0; i < 6; i++) {
        await tester.enterText(textFields.at(i), '${i + 1}');
        await tester.pump();
      }

      // verifyOtp should have been called automatically when 6th digit entered
      expect(notifier.verifyCalled, isTrue);
    });

    testWidgets('shows error when OTP is invalid', (tester) async {
      final notifier = FakeOtpErrorNotifier();
      await tester.pumpWidget(_buildOtpScreen(notifier: notifier));
      await tester.pump();

      final textFields = find.byType(TextField);
      for (int i = 0; i < 6; i++) {
        await tester.enterText(textFields.at(i), '9');
        await tester.pump();
      }

      await tester.pump();
      expect(find.text('Invalid verification code'), findsOneWidget);
    });
  });
}
