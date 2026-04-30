// Tests for FavoritesScreen — the saved restaurants list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:food_delivery_customer/features/restaurants/screens/favorites_screen.dart';
import 'package:food_delivery_customer/features/restaurants/providers/favorites_provider.dart';
import 'package:food_delivery_customer/features/restaurants/models/restaurant_model.dart';
import 'package:food_delivery_customer/core/network/dio_client.dart';

// Fake restaurant data

RestaurantModel _makeRestaurant(String id, String name) => RestaurantModel(
      id: id,
      name: name,
      address: '123 Test St',
      latitude: 9.0,
      longitude: 38.7,
      isOpen: true,
      averageRating: 4.5,
      category: 'Fast Food',
    );

class _FakeDioClient extends DioClient {
  _FakeDioClient() : super();
}

class _FakeNotifier extends FavoritesNotifier {
  _FakeNotifier(Set<String> ids) : super(_FakeDioClient()) {
    state = ids;
  }

  @override
  Future<void> toggle(String restaurantId) async {
    state = state.contains(restaurantId)
        ? ({...state}..remove(restaurantId))
        : {...state, restaurantId};
  }
}

// Helper: build FavoritesScreen with overridden providers

Widget _buildScreen({
  required AsyncValue<List<RestaurantModel>> favAsync,
  Set<String> favIds = const {},
}) {
  final router = GoRouter(
    initialLocation: '/favorites',
    routes: [
      GoRoute(path: '/favorites', builder: (_, __) => const FavoritesScreen()),
      GoRoute(
          path: '/restaurant/:id',
          builder: (_, s) =>
              Scaffold(body: Text('Restaurant ${s.pathParameters['id']}'))),
    ],
  );

  return ProviderScope(
    overrides: [
      favoriteRestaurantsProvider.overrideWith((_) async {
        return favAsync.when(
          data: (d) => d,
          loading: () => throw UnimplementedError(),
          error: (e, _) => throw e,
        );
      }),
      favoritesProvider.overrideWith((_) => _FakeNotifier(favIds)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('FavoritesScreen - structure', () {
    testWidgets('renders Saved Restaurants AppBar', (tester) async {
      await tester.pumpWidget(_buildScreen(favAsync: const AsyncData([])));
      await tester.pumpAndSettle();
      expect(find.text('Saved Restaurants'), findsOneWidget);
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoriteRestaurantsProvider.overrideWith((_) async {
              await Future<void>.delayed(const Duration(hours: 1));
              return <RestaurantModel>[];
            }),
            favoritesProvider.overrideWith((_) => _FakeNotifier({})),
          ],
          child: const MaterialApp(home: FavoritesScreen()),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(hours: 2));
    });

    testWidgets('shows empty state when no favorites', (tester) async {
      await tester.pumpWidget(_buildScreen(favAsync: const AsyncData([])));
      await tester.pumpAndSettle();
      expect(find.text('No saved restaurants yet'), findsOneWidget);
    });

    testWidgets('shows hint text in empty state', (tester) async {
      await tester.pumpWidget(_buildScreen(favAsync: const AsyncData([])));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tap the'), findsOneWidget);
    });
  });

  group('FavoritesScreen - with restaurants', () {
    final restaurants = [
      _makeRestaurant('r1', 'Pizza Palace'),
      _makeRestaurant('r2', 'Burger Barn'),
    ];

    testWidgets('renders restaurant names', (tester) async {
      await tester.pumpWidget(
          _buildScreen(favAsync: AsyncData(restaurants), favIds: {'r1', 'r2'}));
      await tester.pumpAndSettle();
      expect(find.text('Pizza Palace'), findsOneWidget);
      expect(find.text('Burger Barn'), findsOneWidget);
    });

    testWidgets('shows category for each restaurant', (tester) async {
      await tester.pumpWidget(
          _buildScreen(favAsync: AsyncData(restaurants), favIds: {'r1', 'r2'}));
      await tester.pumpAndSettle();
      expect(find.text('Fast Food'), findsWidgets);
    });

    testWidgets('shows Open status for open restaurants', (tester) async {
      await tester.pumpWidget(
          _buildScreen(favAsync: AsyncData(restaurants), favIds: {'r1', 'r2'}));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsWidgets);
    });

    testWidgets('shows filled heart icon for each favorite', (tester) async {
      await tester.pumpWidget(
          _buildScreen(favAsync: AsyncData(restaurants), favIds: {'r1', 'r2'}));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsWidgets);
    });

    testWidgets('shows error message when loading fails', (tester) async {
      await tester.pumpWidget(_buildScreen(
        favAsync: AsyncError('Network error', StackTrace.empty),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Error'), findsOneWidget);
    });
  });
}
