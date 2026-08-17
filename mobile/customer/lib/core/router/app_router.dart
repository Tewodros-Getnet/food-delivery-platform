import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/landing_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/restaurants/screens/restaurant_detail_screen.dart';
import '../../features/restaurants/screens/favorites_screen.dart';
import '../../features/cart/screens/cart_screen.dart';
import '../../features/orders/screens/checkout_screen.dart';
import '../../features/orders/screens/order_tracking_screen.dart';
import '../../features/orders/screens/order_history_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/addresses_screen.dart';
import '../../features/orders/screens/chat_screen.dart';
import '../../features/orders/screens/rating_screen.dart';
import '../../features/orders/screens/dispute_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/notifications/notification_store.dart';

// ── Auth change notifier — tells GoRouter to re-evaluate redirect ─────────────
// The router is created ONCE. When auth changes, this notifier fires and the
// router re-runs its redirect callback without recreating itself.

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
  AuthState get auth => _ref.read(authProvider);
}

final _authNotifierProvider = Provider<_AuthNotifier>(
  (ref) => _AuthNotifier(ref),
);

// ── Router — created once, refreshed via ChangeNotifier ──────────────────────

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_authNotifierProvider);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: notifier,
    redirect: (ctx, state) {
      final auth    = notifier.auth;
      final isAuth  = auth.status == AuthStatus.authenticated;
      final isUnknown = auth.status == AuthStatus.unknown;
      final isPending = auth.status == AuthStatus.pendingVerification;
      final isGuest = auth.status == AuthStatus.guest;
      final loc     = state.matchedLocation;

      final isAuthRoute = loc == '/landing' ||
          loc == '/login' ||
          loc == '/register' ||
          loc == '/verify-otp';

      final isProtected = loc == '/orders' ||
          loc == '/profile' ||
          loc == '/notifications' ||
          loc == '/cart' ||
          loc == '/checkout' ||
          loc == '/addresses' ||
          loc == '/favorites' ||
          loc.startsWith('/order/');

      if (isUnknown) return null;

      if (isPending && loc != '/verify-otp') return '/verify-otp';

      if (auth.status == AuthStatus.unauthenticated) {
        if (!isAuthRoute) return '/landing';
        return null;
      }

      if (isGuest) {
        if (isProtected) return '/landing';
        if (isAuthRoute && loc != '/landing') return '/home';
        return null;
      }

      if (isAuth && isAuthRoute) return '/home';

      return null;
    },
    routes: [
      GoRoute(path: '/landing', builder: (_, __) => const LandingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/verify-otp', builder: (_, __) => const OtpScreen()),

      GoRoute(
        path: '/restaurant/:id',
        builder: (_, s) =>
            RestaurantDetailScreen(restaurantId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(
        path: '/order/:id/track',
        builder: (_, s) =>
            OrderTrackingScreen(orderId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/order/:id/chat',
        builder: (_, s) => ChatScreen(
          orderId: s.pathParameters['id']!,
          currentUserId: s.extra as String,
          title: 'Chat with Rider',
        ),
      ),
      GoRoute(path: '/addresses', builder: (_, __) => const AddressesScreen()),
      GoRoute(path: '/favorites', builder: (_, __) => const FavoritesScreen()),
      GoRoute(
        path: '/order/:id/rate',
        builder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return RatingScreen(
            orderId: s.pathParameters['id']!,
            restaurantName: extra?['restaurantName'] as String?,
            riderName: extra?['riderName'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/order/:id/dispute',
        builder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return DisputeScreen(
            orderId: s.pathParameters['id']!,
            restaurantName: extra?['restaurantName'] as String?,
            itemsSummary: extra?['itemsSummary'] as String?,
          );
        },
      ),

      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) =>
            ScaffoldWithBottomNav(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/orders', builder: (_, __) => const OrderHistoryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});

// ── Bottom nav shell ──────────────────────────────────────────────────────────

class ScaffoldWithBottomNav extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const ScaffoldWithBottomNav({super.key, required this.navigationShell});

  @override
  ConsumerState<ScaffoldWithBottomNav> createState() =>
      _ScaffoldWithBottomNavState();
}

class _ScaffoldWithBottomNavState
    extends ConsumerState<ScaffoldWithBottomNav> {
  @override
  Widget build(BuildContext context) {
    final unreadCount = ref.watch(notificationStoreProvider
        .select((list) => list.where((n) => !n.isRead).length));
    final isGuest =
        ref.watch(authProvider).status == AuthStatus.guest;

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (index) {
          if (isGuest && index > 0) {
            _showGuestSignInSheet(context);
            return;
          }
          widget.navigationShell.goBranch(
            index,
            initialLocation:
                index == widget.navigationShell.currentIndex,
          );
        },
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 8,
        shadowColor: Colors.black12,
        indicatorColor: Colors.orange.withValues(alpha: 0.15),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: Colors.orange),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: Colors.orange),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications, color: Colors.orange),
            ),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Colors.orange),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _showGuestSignInSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline,
                  size: 30, color: Colors.orange),
            ),
            const SizedBox(height: 16),
            const Text('Sign in to continue',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Create an account or sign in to access\nyour orders, alerts, and profile.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.grey[600], fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // Close sheet first, then navigate using the sheet's ctx
                  // which has access to the root GoRouter
                  ctx.go('/register');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Create a free account',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  ctx.go('/login');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Sign in',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Keep browsing',
                  style:
                      TextStyle(color: Colors.grey[500], fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
