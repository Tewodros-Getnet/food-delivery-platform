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

// ── Router provider ───────────────────────────────────────────────────────────
// Uses a Notifier so the GoRouter is created ONCE and never recreated.
// Auth changes trigger redirect re-evaluation via refreshListenable.

class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;
  late final GoRouter router;

  _RouterNotifier(this._ref) {
    // Listen to auth changes and refresh the router redirect
    _ref.listen<AuthState>(authProvider, (_, __) {
      notifyListeners();
    });
    router = _buildRouter();
  }

  AuthState get _auth => _ref.read(authProvider);

  String? _redirect(BuildContext ctx, GoRouterState state) {
    final auth = _auth;
    final loc = state.matchedLocation;

    final isAuthScreen = loc == '/landing' ||
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

    switch (auth.status) {
      case AuthStatus.unknown:
        // Still checking — show splash, never the real home screen
        if (loc != '/splash') return '/splash';
        return null;

      case AuthStatus.pendingVerification:
        if (loc == '/splash') return '/verify-otp';
        if (loc != '/verify-otp') return '/verify-otp';
        return null;

      case AuthStatus.unauthenticated:
        // Leave splash → landing
        if (loc == '/splash') return '/landing';
        if (!isAuthScreen) return '/landing';
        return null;

      case AuthStatus.guest:
        if (loc == '/splash') return '/home';
        if (isProtected) return '/landing';
        return null;

      case AuthStatus.authenticated:
        if (loc == '/splash') return '/home';
        if (isAuthScreen) return '/home';
        return null;
    }
  }

  GoRouter _buildRouter() => GoRouter(
        initialLocation: '/splash',
        refreshListenable: this,
        redirect: _redirect,
        routes: [
          // Splash — shown only during auth resolution
          GoRoute(
            path: '/splash',
            builder: (_, __) => const _SplashScreen(),
          ),
          GoRoute(
              path: '/landing',
              builder: (_, __) => const LandingScreen()),
          GoRoute(
              path: '/login',
              builder: (_, __) => const LoginScreen()),
          GoRoute(
              path: '/register',
              builder: (_, __) => const RegisterScreen()),
          GoRoute(
            path: '/verify-otp',
            builder: (_, s) {
              final extra = s.extra as Map<String, dynamic>?;
              return OtpScreen(
                displayName: extra?['displayName'] as String?,
                phone: extra?['phone'] as String?,
              );
            },
          ),
          GoRoute(
            path: '/restaurant/:id',
            builder: (_, s) => RestaurantDetailScreen(
                restaurantId: s.pathParameters['id']!),
          ),
          GoRoute(
              path: '/cart', builder: (_, __) => const CartScreen()),
          GoRoute(
              path: '/checkout',
              builder: (_, __) => const CheckoutScreen()),
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
          GoRoute(
              path: '/addresses',
              builder: (_, __) => const AddressesScreen()),
          GoRoute(
              path: '/favorites',
              builder: (_, __) => const FavoritesScreen()),
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
                GoRoute(
                    path: '/home',
                    builder: (_, __) => const HomeScreen()),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/orders',
                    builder: (_, __) => const OrderHistoryScreen()),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/notifications',
                    builder: (_, __) => const NotificationsScreen()),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/profile',
                    builder: (_, __) => const ProfileScreen()),
              ]),
            ],
          ),
        ],
      );
}

// Single global notifier — created once, never disposed
final _routerNotifierProvider =
    Provider<_RouterNotifier>((ref) => _RouterNotifier(ref));

// Exposes just the GoRouter instance
final appRouterProvider = Provider<GoRouter>((ref) {
  return ref.watch(_routerNotifierProvider).router;
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/images/logo.png',
                width: 110,
                height: 110,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
            // Guest taps protected tab → go to landing
            GoRouter.of(context).go('/landing');
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
}
