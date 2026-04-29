import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:food_delivery_customer/features/auth/providers/auth_provider.dart';
import 'package:food_delivery_customer/features/auth/screens/login_screen.dart';
import 'package:food_delivery_customer/features/auth/services/auth_service.dart';
import 'package:food_delivery_customer/features/auth/models/user_model.dart';
import 'package:food_delivery_customer/core/network/dio_client.dart';
import 'package:food_delivery_customer/core/storage/secure_storage.dart';

// ── Fake AuthService stub ─────────────────────────────────────────────────────
// Uses real constructors to satisfy null safety, overrides all methods.

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(DioClient(), SecureStorageService());
  @override
  Future<bool> isLoggedIn() async => false;
  @override
  Future<void> logout() async {}
}

// ── Fake notifiers ────────────────────────────────────────────────────────────

class FakeLoginNotifier extends AuthNotifier {
  FakeLoginNotifier() : super(_FakeAuthService());
  bool loginCalled = false;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<void> login(String email, String password) async {
    loginCalled = true;
    lastEmail = email;
    lastPassword = password;
    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: UserModel(
        id: 'test-id',
        email: email,
        role: 'customer',
        displayName: 'Test User',
        status: '',
      ),
      isLoading: false,
    );
  }
}

class FakeLoginErrorNotifier extends AuthNotifier {
  FakeLoginErrorNotifier() : super(_FakeAuthService());

  @override
  Future<void> login(String email, String password) async {
    state = state.copyWith(
      isLoading: false,
      error: 'Invalid credentials',
      status: AuthStatus.unauthenticated,
    );
  }
}

class FakeLoginLoadingNotifier extends AuthNotifier {
  FakeLoginLoadingNotifier() : super(_FakeAuthService());

  @override
  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true);
    // Never resolves — simulates loading state
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

Widget _buildLoginScreen({AuthNotifier? notifier}) {
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('Home'))),
      GoRoute(
          path: '/register',
          builder: (_, __) => const Scaffold(body: Text('Register'))),
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
  group('LoginScreen — UI structure', () {
    testWidgets('renders email and password fields', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('renders Sign In button', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('renders Create account link', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pumpAndSettle();

      expect(find.text('New here? Create account'), findsOneWidget);
    });

    testWidgets('password field has show/hide toggle', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('LoginScreen — validation', () {
    testWidgets('shows error for invalid email', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'notanemail');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('shows error for short password', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'test@test.com');
      await tester.enterText(find.byType(TextFormField).last, 'short');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Min 8 characters'), findsOneWidget);
    });

    testWidgets('does not call login when form is invalid', (tester) async {
      final notifier = FakeLoginNotifier();
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(notifier.loginCalled, isFalse);
    });
  });

  group('LoginScreen — interactions', () {
    testWidgets('calls login with correct credentials', (tester) async {
      final notifier = FakeLoginNotifier();
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'user@test.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(notifier.loginCalled, isTrue);
      expect(notifier.lastEmail, 'user@test.com');
      expect(notifier.lastPassword, 'password123');
    });

    testWidgets('shows error container when auth error occurs', (tester) async {
      final notifier = FakeLoginErrorNotifier();
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'user@test.com');
      await tester.enterText(find.byType(TextFormField).last, 'wrongpassword');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid credentials'), findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(_buildLoginScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets('loading state disables button', (tester) async {
      final notifier = FakeLoginLoadingNotifier();
      await tester.pumpWidget(_buildLoginScreen(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'user@test.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(notifier.state.isLoading, isTrue);
    });
  });
}
