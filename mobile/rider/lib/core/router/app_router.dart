import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/delivery/screens/home_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/home',
    redirect: (ctx, state) {
      final isAuth = auth.status == AuthStatus.authenticated;
      final isUnknown = auth.status == AuthStatus.unknown;
      final isPublic =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      if (isUnknown) return null;
      if (!isAuth && !isPublic) return '/login';
      if (isAuth && isPublic) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (_, __) => const RiderHomeScreen()),
    ],
  );
});
