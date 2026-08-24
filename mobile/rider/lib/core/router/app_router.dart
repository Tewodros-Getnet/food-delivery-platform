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
    initialLocation: '/home',
    redirect: (ctx, state) {
      final loc = state.matchedLocation;

      final isUnknown  = auth.status == AuthStatus.unknown;
      final isPending  = auth.status == AuthStatus.pendingVerification;
      final isAuth     = auth.status == AuthStatus.authenticated;

      final isPublicRoute = loc == '/login' ||
          loc == '/register' ||
          loc == '/verify-otp';

      // ── 1. Still resolving token — wait ────────────────────────────────
      if (isUnknown) return null;

      // ── 2. OTP pending — lock to /verify-otp ──────────────────────────
      if (isPending && loc != '/verify-otp') return '/verify-otp';

      // ── 3. Not authenticated — send to login ───────────────────────────
      if (!isAuth && !isPending && !isPublicRoute) return '/login';

      // ── 4. Authenticated + on a public route ───────────────────────────
      if (isAuth && isPublicRoute) {
        return _postAuthDestination(auth);
      }

      // ── 5. Authenticated + on a protected route ────────────────────────
      if (isAuth && !isPublicRoute) {
        // Invitation status still being fetched — let current screen stay
        if (auth.hasAcceptedInvitation == null) return null;

        // Has a pending invitation — must view it first
        if (auth.invitationData != null &&
            loc != '/invitation') {
          return '/invitation';
        }

        // No invitation yet — keep on /waiting
        if (auth.hasAcceptedInvitation == false &&
            auth.invitationData == null &&
            loc != '/waiting') {
          return '/waiting';
        }

        // Has accepted invitation — /waiting and /invitation are no longer valid
        if (auth.hasAcceptedInvitation == true &&
            (loc == '/waiting' || loc == '/invitation')) {
          return '/home';
        }
      }

      return null;
    },
    routes: [
      // ── Auth ────────────────────────────────────────────────────────────
      GoRoute(path: '/login',      builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register',   builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/verify-otp', builder: (_, __) => const OtpScreen()),

      // ── Onboarding / invitation ──────────────────────────────────────────
      GoRoute(path: '/waiting',    builder: (_, __) => const WaitingForInvitationScreen()),
      GoRoute(path: '/invitation', builder: (_, __) => const InvitationScreen()),

      // ── Main app ─────────────────────────────────────────────────────────
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

/// Where to send an authenticated user who is currently on a public route.
String _postAuthDestination(AuthState auth) {
  if (auth.hasAcceptedInvitation == null) return '/home'; // still loading
  if (auth.invitationData != null)         return '/invitation';
  if (auth.hasAcceptedInvitation == false) return '/waiting';
  return '/home';
}
