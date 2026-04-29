import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:food_delivery_customer/features/auth/providers/auth_provider.dart';
import 'package:food_delivery_customer/features/auth/screens/register_screen.dart';
import 'package:food_delivery_customer/features/auth/services/auth_service.dart';
import 'package:food_delivery_customer/core/network/dio_client.dart';
import 'package:food_delivery_customer/core/storage/secure_storage.dart';

// ── Fake AuthService (minimal stub) ──────────────────────────────────────────

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(DioClient(), SecureStorageService());
  @override
  Future<bool> isLoggedIn() async => false;
  @override
  Future<void> logout() async {}
}

// ── Fake notifiers ────────────────────────────────────────────────────────────

class FakeRegisterNotifier extends AuthNotifier {
  FakeRegisterNotifier() : super(_FakeAuthService());
  bool registerCalled = false;
  String? lastEmail;

  @override
  Future<void> register(String email, String password) async {
    registerCalled = true;
    lastEmail = email;
    state = state.copyWith(
      status: AuthStatus.pendingVerification,
      pendingUserId: 'test-user-id',
      isLoading: false,
    );
  }
}

class FakeRegisterErrorNotifier extends AuthNotifier {
  FakeRegisterErrorNotifier() : super(_FakeAuthService());

  @override
  Future<void> register(String email, String password) async {
    state = state.copyWith(
      isLoading: false,
      error: 'Email already registered',
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

Widget _buildRegisterScreen({AuthNotifier? notifier}) {
  final router = GoRouter(
    initialLocation: '/register',
    routes: [
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: '/verify-otp',
          builder: (_, __) => const Scaffold(body: Text('OTP'))),
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
  group('RegisterScreen — UI structure', () {
    testWidgets('renders email and password fields', (tester) async {
      await tester.pumpWidget(_buildRegisterScreen());
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password (min 8 chars)'), findsOneWidget);
    });

    testWidgets('renders Create Account button', (tester) async {
      await tester.pumpWidget(_buildRegisterScreen());
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsWidgets);
    });

    testWidgets('renders sign in link', (tester) async {
      await tester.pumpWidget(_buildRegisterScreen());
      await tester.pumpAndSettle();

      expect(find.text('Already have an account? Sign in'), findsOneWidget);
    });

    testWidgets('has password show/hide toggle', (tester) async {
      await tester.pumpWidget(_buildRegisterScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('RegisterScreen — validation', () {
    testWidgets('shows error for invalid email', (tester) async {
      await tester.pumpWidget(_buildRegisterScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'notanemail');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('shows error for short password', (tester) async {
      await tester.pumpWidget(_buildRegisterScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'test@test.com');
      await tester.enterText(find.byType(TextFormField).last, 'short');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Min 8 characters'), findsOneWidget);
    });
  });

  group('RegisterScreen — interactions', () {
    testWidgets('calls register with correct email', (tester) async {
      final notifier = FakeRegisterNotifier();
      await tester.pumpWidget(_buildRegisterScreen(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'new@test.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(notifier.registerCalled, isTrue);
      expect(notifier.lastEmail, 'new@test.com');
    });

    testWidgets('shows error when registration fails', (tester) async {
      final notifier = FakeRegisterErrorNotifier();
      await tester.pumpWidget(_buildRegisterScreen(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField).first, 'existing@test.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Email already registered'), findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(_buildRegisterScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });
}
