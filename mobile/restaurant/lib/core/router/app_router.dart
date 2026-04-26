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
import '../../features/restaurant/screens/operating_hours_screen.dart';
import '../../features/restaurant/screens/analytics_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/riders/screens/my_riders_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/orders',
    redirect: (ctx, state) {
      final isAuth = auth.status == AuthStatus.authenticated;
      final isUnknown = auth.status == AuthStatus.unknown;
      final isPublic = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/verify-otp';
      if (isUnknown) return null;
      if (!isAuth && !isPublic) return '/login';
      if (auth.status == AuthStatus.pendingVerification &&
          state.matchedLocation != '/verify-otp') return '/verify-otp';
      if (isAuth && isPublic) return '/orders';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/verify-otp', builder: (_, __) => const OtpScreen()),
      GoRoute(path: '/orders', builder: (_, __) => const OrdersScreen()),
      GoRoute(path: '/riders', builder: (_, __) => const MyRidersScreen()),
      GoRoute(
          path: '/setup', builder: (_, __) => const RestaurantSetupScreen()),
      GoRoute(
          path: '/profile',
          builder: (_, __) => const RestaurantProfileScreen()),
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
      GoRoute(
        path: '/hours',
        builder: (_, __) => const OperatingHoursScreen(),
      ),
      GoRoute(
        path: '/analytics',
        builder: (_, __) => const RestaurantAnalyticsScreen(),
      ),
    ],
  );
});
