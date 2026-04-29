import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:food_delivery_customer/features/orders/screens/order_history_screen.dart';
import 'package:food_delivery_customer/features/orders/models/order_model.dart';
import 'package:food_delivery_customer/features/orders/services/order_service.dart';
import 'package:food_delivery_customer/core/network/dio_client.dart';

// ── Fake OrderService ─────────────────────────────────────────────────────────

class _FakeDioClient extends DioClient {
  _FakeDioClient() : super();
}

class FakeOrderService extends OrderService {
  final List<OrderModel> orders;
  FakeOrderService(this.orders) : super(_FakeDioClient());

  @override
  Future<List<OrderModel>> getOrders() async => orders;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

OrderModel _makeOrder({
  String id = 'aaaabbbb-cccc-dddd-eeee-ffffffffffff',
  String status = 'delivered',
  double total = 100.0,
  String? restaurantName = 'Burger Palace',
  String? itemsSummary = 'Burger x2',
}) =>
    OrderModel(
      id: id,
      customerId: 'cust-1',
      restaurantId: 'rest-1',
      status: status,
      subtotal: 90.0,
      deliveryFee: 10.0,
      total: total,
      createdAt: DateTime(2024, 1, 15, 12, 0),
      restaurantName: restaurantName,
      itemsSummary: itemsSummary,
    );

Widget _buildOrderHistory(List<OrderModel> orders) {
  final router = GoRouter(
    initialLocation: '/orders',
    routes: [
      GoRoute(path: '/orders', builder: (_, __) => const OrderHistoryScreen()),
      GoRoute(
          path: '/order/:id/track',
          builder: (_, s) =>
              Scaffold(body: Text('Track ${s.pathParameters['id']}'))),
      GoRoute(
          path: '/cart',
          builder: (_, __) => const Scaffold(body: Text('Cart'))),
    ],
  );

  return ProviderScope(
    overrides: [
      orderServiceProvider.overrideWithValue(FakeOrderService(orders)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('OrderHistoryScreen — empty state', () {
    testWidgets('shows empty state when no orders', (tester) async {
      await tester.pumpWidget(_buildOrderHistory([]));
      await tester.pumpAndSettle();

      expect(find.text('No orders yet'), findsOneWidget);
    });
  });

  group('OrderHistoryScreen — with orders', () {
    testWidgets('shows restaurant name', (tester) async {
      await tester.pumpWidget(_buildOrderHistory([_makeOrder()]));
      await tester.pumpAndSettle();

      expect(find.text('Burger Palace'), findsOneWidget);
    });

    testWidgets('shows items summary', (tester) async {
      await tester.pumpWidget(_buildOrderHistory([_makeOrder()]));
      await tester.pumpAndSettle();

      expect(find.text('Burger x2'), findsOneWidget);
    });

    testWidgets('shows order total', (tester) async {
      await tester.pumpWidget(_buildOrderHistory([_makeOrder(total: 150.0)]));
      await tester.pumpAndSettle();

      expect(find.text('ETB 150.00'), findsOneWidget);
    });

    testWidgets('shows status chip', (tester) async {
      await tester
          .pumpWidget(_buildOrderHistory([_makeOrder(status: 'delivered')]));
      await tester.pumpAndSettle();

      expect(find.text('DELIVERED'), findsOneWidget);
    });

    testWidgets('shows Reorder button for delivered orders', (tester) async {
      await tester
          .pumpWidget(_buildOrderHistory([_makeOrder(status: 'delivered')]));
      await tester.pumpAndSettle();

      expect(find.text('Reorder'), findsOneWidget);
    });

    testWidgets('shows Reorder button for cancelled orders', (tester) async {
      await tester
          .pumpWidget(_buildOrderHistory([_makeOrder(status: 'cancelled')]));
      await tester.pumpAndSettle();

      expect(find.text('Reorder'), findsOneWidget);
    });

    testWidgets('shows Track button for active orders', (tester) async {
      await tester
          .pumpWidget(_buildOrderHistory([_makeOrder(status: 'confirmed')]));
      await tester.pumpAndSettle();

      expect(find.text('Track'), findsOneWidget);
    });

    testWidgets('does not show Track for delivered orders', (tester) async {
      await tester
          .pumpWidget(_buildOrderHistory([_makeOrder(status: 'delivered')]));
      await tester.pumpAndSettle();

      expect(find.text('Track'), findsNothing);
    });

    testWidgets('shows Rate button for delivered orders', (tester) async {
      await tester
          .pumpWidget(_buildOrderHistory([_makeOrder(status: 'delivered')]));
      await tester.pumpAndSettle();

      expect(find.text('Rate'), findsOneWidget);
    });

    testWidgets('shows Report a problem for delivered orders', (tester) async {
      await tester
          .pumpWidget(_buildOrderHistory([_makeOrder(status: 'delivered')]));
      await tester.pumpAndSettle();

      expect(find.text('Report a problem'), findsOneWidget);
    });

    testWidgets('shows multiple orders', (tester) async {
      await tester.pumpWidget(_buildOrderHistory([
        _makeOrder(
            id: 'aaaabbbb-cccc-dddd-eeee-111111111111',
            restaurantName: 'Burger Palace'),
        _makeOrder(
            id: 'aaaabbbb-cccc-dddd-eeee-222222222222',
            restaurantName: 'Pizza Hub'),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Burger Palace'), findsOneWidget);
      expect(find.text('Pizza Hub'), findsOneWidget);
    });

    testWidgets('shows pending_acceptance status chip', (tester) async {
      await tester.pumpWidget(
          _buildOrderHistory([_makeOrder(status: 'pending_acceptance')]));
      await tester.pumpAndSettle();

      expect(find.text('PENDING ACCEPTANCE'), findsOneWidget);
    });
  });
}
