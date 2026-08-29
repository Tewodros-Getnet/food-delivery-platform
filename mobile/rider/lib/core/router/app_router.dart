import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/invitation_screen.dart';
import '../../features/auth/screens/waiting_for_invitation_screen.dart';
import '../../features/delivery/screens/home_screen.dart';
import '../../features/delivery/screens/earnings_screen.dart';
import '../../features/delivery/screens/chat_screen.dart';
import '../../features/profile/screens/profile_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (ctx, state) {
      final loc = state.matchedLocation;

      final isUnknown  = auth.status == AuthStatus.unknown;
      final isPending  = auth.status == AuthStatus.pendingVerification;
      final isAuth     = auth.status == AuthStatus.authenticated;

      final isPublicRoute = loc == '/login' ||
          loc == '/register' ||
          loc == '/verify-otp';

      // ── Still resolving — stay on splash ──────────────────────────────
      if (isUnknown) {
        if (loc != '/splash') return '/splash';
        return null;
      }

      // ── Once resolved, leave splash immediately ───────────────────────
      if (loc == '/splash') {
        if (isPending) return '/verify-otp';
        if (!isAuth)   return '/login';
        return _postAuthDestination(auth);
      }

      // ── OTP pending ───────────────────────────────────────────────────
      if (isPending && loc != '/verify-otp') return '/verify-otp';

      // ── Not authenticated ─────────────────────────────────────────────
      if (!isAuth && !isPending && !isPublicRoute) return '/login';

      // ── Authenticated + on a public route ─────────────────────────────
      if (isAuth && isPublicRoute) return _postAuthDestination(auth);

      // ── Authenticated + on a protected route ─────────────────────────
      if (isAuth && !isPublicRoute) {
        if (auth.hasAcceptedInvitation == null) return null;
        if (auth.invitationData != null && loc != '/invitation') {
          return '/invitation';
        }
        if (auth.hasAcceptedInvitation == false &&
            auth.invitationData == null &&
            loc != '/waiting') {
          return '/waiting';
        }
        if (auth.hasAcceptedInvitation == true &&
            (loc == '/waiting' || loc == '/invitation')) {
          return '/home';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),

      GoRoute(path: '/login',      builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register',   builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/verify-otp', builder: (_, __) => const OtpScreen()),

      GoRoute(path: '/waiting',    builder: (_, __) => const WaitingForInvitationScreen()),
      GoRoute(path: '/invitation', builder: (_, __) => const InvitationScreen()),

      GoRoute(path: '/home',     builder: (_, __) => const RiderHomeScreen()),
      GoRoute(path: '/earnings', builder: (_, __) => const EarningsScreen()),
      GoRoute(path: '/profile',  builder: (_, __) => const RiderProfileScreen()),
      GoRoute(
        path: '/chat/:orderId',
        builder: (_, s) => RiderChatScreen(
          orderId: s.pathParameters['orderId']!,
          currentUserId: s.extra as String? ?? '',
        ),
      ),
    ],
  );
});

String _postAuthDestination(AuthState auth) {
  if (auth.hasAcceptedInvitation == null) return '/home';
  if (auth.invitationData != null)         return '/invitation';
  if (auth.hasAcceptedInvitation == false) return '/waiting';
  return '/home';
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/images/logo.jpg',
                width: 110,
                height: 110,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
