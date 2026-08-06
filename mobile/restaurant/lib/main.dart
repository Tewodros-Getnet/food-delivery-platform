import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'l10n/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/providers/locale_provider.dart';
import 'core/network/dio_client.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/notifications/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const ProviderScope(child: RestaurantApp()));
}

class RestaurantApp extends ConsumerStatefulWidget {
  const RestaurantApp({super.key});

  @override
  ConsumerState<RestaurantApp> createState() => _RestaurantAppState();
}

class _RestaurantAppState extends ConsumerState<RestaurantApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(fcmServiceProvider).initialize(context);

      // Layer 2: force logout when refresh token is rejected
      ref.listen<AsyncValue<void>>(sessionExpiredProvider, (_, next) {
        next.whenData((_) async {
          await ref.read(authProvider.notifier).logout();
          if (!mounted) return;
          final router = ref.read(appRouterProvider);
          router.go('/login');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your session has expired. Please log in again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Restaurant Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      locale: ref.watch(localeProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
