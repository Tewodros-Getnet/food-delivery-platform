// Tests for CheckoutScreen — order summary, address selection, and pay button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:food_delivery_customer/features/orders/screens/checkout_screen.dart';
import 'package:food_delivery_customer/features/cart/providers/cart_provider.dart';
import 'package:food_delivery_customer/features/cart/models/cart_item.dart';
import 'package:food_delivery_customer/features/restaurants/models/restaurant_model.dart';
import 'package:food_delivery_customer/core/network/dio_client.dart';

// Fake DioClient

class _FakeDioClient extends DioClient {
  _FakeDioClient() : super();
}

// Fake CartNotifier with pre-populated items

class FakeCartNotifier extends CartNotifier {
  FakeCartNotifier(List<CartItem> items, String? restaurantId) {
    state = CartState(items: items, restaurantId: restaurantId);
  }

  @override
  bool addItem(MenuItemModel item, String restaurantId,
          {List<SelectedModifier> selectedModifiers = const []}) =>
      false;

  @override
  void removeItem(String menuItemId) {}

  @override
  void clear() {}
}

MenuItemModel _makeMenuItem(String id, String name, double price) =>
    MenuItemModel(
      id: id,
      restaurantId: 'rest-1',
      name: name,
      price: price,
      imageUrl: '',
      available: true,
    );

CartItem _makeCartItem(String id, String name, double price, int qty) =>
    CartItem(
      menuItem: _makeMenuItem(id, name, price),
      quantity: qty,
    );

// Helper: build CheckoutScreen

Widget _buildCheckout({
  List<CartItem> items = const [],
  String? restaurantId = 'rest-1',
  List<Map<String, dynamic>> addresses = const [],
}) {
  final router = GoRouter(
    initialLocation: '/checkout',
    routes: [
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(
          path: '/addresses',
          builder: (_, __) => const Scaffold(body: Text('Addresses'))),
      GoRoute(
          path: '/order/:id/track',
          builder: (_, s) =>
              Scaffold(body: Text('Track ${s.pathParameters['id']}'))),
    ],
  );

  return ProviderScope(
    overrides: [
      cartProvider.overrideWith((_) => FakeCartNotifier(items, restaurantId)),
      dioClientProvider.overrideWithValue(_FakeDioClient()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('CheckoutScreen - structure', () {
    testWidgets('renders Checkout AppBar', (tester) async {
      await tester.pumpWidget(_buildCheckout());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Checkout'), findsOneWidget);
    });

    testWidgets('renders Order Summary section', (tester) async {
      await tester.pumpWidget(_buildCheckout());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Order Summary'), findsOneWidget);
    });

    testWidgets('renders Delivery Address section', (tester) async {
      await tester.pumpWidget(_buildCheckout());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Delivery Address'), findsOneWidget);
    });

    testWidgets('renders Pay with Chapa button', (tester) async {
      await tester.pumpWidget(_buildCheckout());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Pay with Chapa'), findsOneWidget);
    });
  });

  group('CheckoutScreen - order summary', () {
    testWidgets('shows cart item names and quantities', (tester) async {
      final items = [
        _makeCartItem('m1', 'Burger', 80.0, 2),
        _makeCartItem('m2', 'Fries', 30.0, 1),
      ];
      await tester.pumpWidget(_buildCheckout(items: items));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Burger'), findsOneWidget);
      expect(find.textContaining('Fries'), findsOneWidget);
      expect(find.textContaining('× 2'), findsOneWidget);
    });

    testWidgets('shows subtotal', (tester) async {
      final items = [_makeCartItem('m1', 'Burger', 80.0, 2)];
      await tester.pumpWidget(_buildCheckout(items: items));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // subtotal = 80 * 2 = 160
      expect(find.textContaining('160.00'), findsWidgets);
    });

    testWidgets('shows Subtotal label', (tester) async {
      await tester.pumpWidget(
          _buildCheckout(items: [_makeCartItem('m1', 'Burger', 80.0, 1)]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Subtotal'), findsOneWidget);
    });

    testWidgets('shows Delivery fee label', (tester) async {
      await tester.pumpWidget(
          _buildCheckout(items: [_makeCartItem('m1', 'Burger', 80.0, 1)]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Delivery fee'), findsOneWidget);
    });
  });

  group('CheckoutScreen - address section', () {
    testWidgets('shows Delivery Address section header', (tester) async {
      await tester.pumpWidget(_buildCheckout());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Delivery Address'), findsOneWidget);
    });
  });

  group('CheckoutScreen - validation', () {
    testWidgets('Pay button is present', (tester) async {
      await tester.pumpWidget(
          _buildCheckout(items: [_makeCartItem('m1', 'Burger', 80.0, 1)]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Pay with Chapa'), findsOneWidget);
    });
  });
}
