import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/restaurants/screens/restaurant_detail_screen.dart';
import '../../features/cart/screens/cart_screen.dart';
import '../../features/orders/screens/checkout_screen.dart';
import '../../features/orders/screens/order_tracking_screen.dart';
import '../../features/orders/screens/order_history_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/addresses_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/home',
    redirect: (ctx, state) {
      final isAuth = auth.status == AuthStatus.authenticated;
      final isUnknown = auth.status == AuthStatus.unknown;
      final isPublic = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      if (isUnknown) return null;
      if (!isAuth && !isPublic) return '/login';
      if (isAuth && isPublic) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(
          path: '/restaurant/:id',
          builder: (_, s) =>
              RestaurantDetailScreen(restaurantId: s.pathParameters['id']!)),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(
          path: '/order/:id/track',
          builder: (_, s) =>
              OrderTrackingScreen(orderId: s.pathParameters['id']!)),
      GoRoute(path: '/orders', builder: (_, __) => const OrderHistoryScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/addresses', builder: (_, __) => const AddressesScreen()),
    ],
  );
});
