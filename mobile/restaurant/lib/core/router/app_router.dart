import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/orders/screens/orders_screen.dart';
import '../../features/menu/screens/menu_screen.dart';
import '../../features/menu/screens/modifiers_screen.dart';
import '../../features/restaurant/screens/restaurant_setup_screen.dart';
import '../../features/restaurant/screens/pending_approval_screen.dart';
import '../../features/restaurant/screens/operating_hours_screen.dart';
import '../../features/restaurant/screens/analytics_screen.dart';
import '../../features/restaurant/screens/reviews_screen.dart';
import '../../features/restaurant/screens/banner_screen.dart';
import '../../features/restaurant/screens/images_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/riders/screens/my_riders_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/orders',
    redirect: (ctx, state) {
      final loc = state.matchedLocation;

      final isUnknown  = auth.status == AuthStatus.unknown;
      final isPending  = auth.status == AuthStatus.pendingVerification;
      final isAuth     = auth.status == AuthStatus.authenticated;

      final isPublicRoute = loc == '/login' ||
          loc == '/register' ||
          loc == '/verify-otp';

      // ── 1. Still resolving stored token — don't redirect yet ──────────
      if (isUnknown) return null;

      // ── 2. OTP pending — lock to /verify-otp ─────────────────────────
      if (isPending && loc != '/verify-otp') return '/verify-otp';

      // ── 3. Not authenticated — send to login ──────────────────────────
      if (!isAuth && !isPending && !isPublicRoute) return '/login';

      // ── 4. Authenticated + on a public route — decide where to go ────
      if (isAuth && isPublicRoute) {
        return _postAuthDestination(auth);
      }

      // ── 5. Authenticated + on a protected route ───────────────────────
      if (isAuth && !isPublicRoute) {
        // hasRestaurant is still null → restaurant check in flight, wait
        if (auth.hasRestaurant == null) return null;

        // No restaurant yet — only allow /setup
        if (auth.hasRestaurant == false && loc != '/setup') return '/setup';

        // Restaurant pending approval — only allow /pending-approval & /setup
        if (auth.hasRestaurant == true &&
            auth.restaurantStatus == 'pending' &&
            loc != '/pending-approval' &&
            loc != '/setup') {
          return '/pending-approval';
        }

        // Restaurant rejected — only allow /setup (re-submit)
        if (auth.hasRestaurant == true &&
            auth.restaurantStatus == 'rejected' &&
            loc != '/setup') {
          return '/setup';
        }
      }

      return null;
    },
    routes: [
      // ── Auth ────────────────────────────────────────────────────────────
      GoRoute(path: '/login',      builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register',   builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/verify-otp', builder: (_, __) => const OtpScreen()),

      // ── Onboarding ──────────────────────────────────────────────────────
      GoRoute(path: '/setup',            builder: (_, __) => const RestaurantSetupScreen()),
      GoRoute(path: '/pending-approval', builder: (_, __) => const PendingApprovalScreen()),

      // ── Main app ────────────────────────────────────────────────────────
      GoRoute(path: '/orders',  builder: (_, __) => const OrdersScreen()),
      GoRoute(path: '/riders',  builder: (_, __) => const MyRidersScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const RestaurantProfileScreen()),

      GoRoute(
        path: '/menu/:restaurantId',
        builder: (_, s) =>
            MenuScreen(restaurantId: s.pathParameters['restaurantId']!),
      ),
      GoRoute(
        path: '/menu-item/:id/modifiers',
        builder: (_, s) => ModifiersScreen(
          menuItemId: s.pathParameters['id']!,
          menuItemName: s.uri.queryParameters['name'] ?? 'Item',
        ),
      ),
      GoRoute(path: '/hours',     builder: (_, __) => const OperatingHoursScreen()),
      GoRoute(path: '/analytics', builder: (_, __) => const RestaurantAnalyticsScreen()),
      GoRoute(path: '/reviews',   builder: (_, __) => const RestaurantReviewsScreen()),
      GoRoute(path: '/banner',    builder: (_, __) => const PromoBannerScreen()),
      GoRoute(path: '/images',    builder: (_, __) => const RestaurantImagesScreen()),
    ],
  );
});

/// Decides where an authenticated user should land after coming from a
/// public route (login / register / OTP).
String _postAuthDestination(AuthState auth) {
  // Restaurant check still in flight — go to orders, which handles its own
  // loading/empty state gracefully
  if (auth.hasRestaurant == null) return '/orders';
  if (auth.hasRestaurant == false) return '/setup';
  if (auth.restaurantStatus == 'pending') return '/pending-approval';
  if (auth.restaurantStatus == 'rejected') return '/setup';
  return '/orders';
}
