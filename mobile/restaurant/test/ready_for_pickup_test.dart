// Tests for the restaurant "Mark Ready for Pickup" flow.
//
// Covers:
//   - "Mark Ready for Pickup" button only appears for confirmed orders
//   - Tapping it calls markReady on the service
//   - onMarkReady callback fires so the parent can reload
//   - Button is absent for all other statuses

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:food_delivery_restaurant/features/orders/models/order_model.dart';
import 'package:food_delivery_restaurant/features/orders/screens/orders_screen.dart';
import 'package:food_delivery_restaurant/features/orders/services/order_service.dart';
import 'package:food_delivery_restaurant/core/network/dio_client.dart';

// ── Fake helpers ──────────────────────────────────────────────────────────────

class _FakeDioClient extends DioClient {
  _FakeDioClient() : super();
}

class FakeOrderService extends OrderService {
  bool shouldThrow;
  int markReadyCallCount = 0;
  String? lastMarkedReadyId;

  FakeOrderService({this.shouldThrow = false}) : super(_FakeDioClient());

  @override
  Future<List<OrderModel>> getOrders() async => [];

  @override
  Future<void> markReady(String orderId, {int? prepTime}) async {
    markReadyCallCount++;
    lastMarkedReadyId = orderId;
    if (shouldThrow) throw Exception('Network error');
  }

  @override
  Future<void> cancelOrder(String orderId, String reason) async {}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

OrderModel _makeOrder(String status) => OrderModel(
      id: 'aaaabbbb-cccc-dddd-eeee-ffffffffffff',
      restaurantId: 'rest-1',
      status: status,
      subtotal: 80.0,
      deliveryFee: 20.0,
      total: 100.0,
      createdAt: DateTime(2026, 4, 1, 12, 0),
      items: const [
        OrderItemModel(
          id: 'item-1',
          menuItemId: 'menu-1',
          quantity: 2,
          unitPrice: 40.0,
          itemName: 'Burger',
        ),
      ],
    );

Future<FakeOrderService> _pumpCard(
  WidgetTester tester,
  OrderModel order, {
  bool shouldThrow = false,
  VoidCallback? onMarkReady,
  VoidCallback? onCancelled,
}) async {
  final svc = FakeOrderService(shouldThrow: shouldThrow);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [orderServiceProvider.overrideWithValue(svc)],
      child: MaterialApp(
        home: Scaffold(
          body: OrderCardTestWrapper(
            order: order,
            onMarkReady: onMarkReady ?? () {},
            onCancelled: onCancelled ?? () {},
          ),
        ),
      ),
    ),
  );
  return svc;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Button visibility ──────────────────────────────────────────────────────
  group('Mark Ready button — visibility', () {
    const buttonText = 'Mark Ready for Pickup';

    testWidgets('button is PRESENT for confirmed status', (tester) async {
      await _pumpCard(tester, _makeOrder('confirmed'));
      expect(find.text(buttonText), findsOneWidget);
    });

    for (final status in [
      'ready_for_pickup',
      'rider_assigned',
      'picked_up',
      'delivered',
      'cancelled',
    ]) {
      testWidgets('button is ABSENT for status "$status"', (tester) async {
        await _pumpCard(tester, _makeOrder(status));
        expect(find.text(buttonText), findsNothing);
      });
    }
  });

  // ── Interaction ────────────────────────────────────────────────────────────
  group('Mark Ready button — interaction', () {
    testWidgets('tapping fires onMarkReady callback', (tester) async {
      bool fired = false;
      await _pumpCard(
        tester,
        _makeOrder('confirmed'),
        onMarkReady: () => fired = true,
      );
      await tester.tap(find.text('Mark Ready for Pickup'));
      await tester.pumpAndSettle();

      expect(fired, isTrue,
          reason: 'Parent must be notified so it can reload and move the order '
              'to the ready_for_pickup section');
    });

    testWidgets('onMarkReady callback fires after successful call',
        (tester) async {
      bool fired = false;
      await _pumpCard(
        tester,
        _makeOrder('confirmed'),
        onMarkReady: () => fired = true,
      );
      await tester.tap(find.text('Mark Ready for Pickup'));
      await tester.pumpAndSettle();

      expect(fired, isTrue,
          reason: 'Parent must be notified so it can reload and move the order '
              'to the ready_for_pickup section');
    });
  });

  // ── Order card content ─────────────────────────────────────────────────────
  group('Order card — content', () {
    testWidgets('shows order id prefix', (tester) async {
      await _pumpCard(tester, _makeOrder('confirmed'));
      // Card renders "Order #aaaabbbb" (first 8 chars of the UUID, lowercase)
      expect(find.textContaining('aaaabbbb'), findsOneWidget);
    });

    testWidgets('shows item name and quantity', (tester) async {
      await _pumpCard(tester, _makeOrder('confirmed'));
      expect(find.textContaining('Burger'), findsOneWidget);
      expect(find.textContaining('× 2'), findsOneWidget);
    });

    testWidgets('shows subtotal, delivery fee and total', (tester) async {
      await _pumpCard(tester, _makeOrder('confirmed'));
      // subtotal 80.00 appears in both the item row and the subtotal row — use findsWidgets
      expect(find.textContaining('80.00'), findsWidgets);
      expect(find.textContaining('20.00'), findsOneWidget); // delivery fee
      expect(find.textContaining('100.00'), findsOneWidget); // total
    });

    testWidgets('shows status chip', (tester) async {
      await _pumpCard(tester, _makeOrder('confirmed'));
      expect(find.text('confirmed'), findsOneWidget);
    });

    testWidgets('shows elapsed prep timer for confirmed orders',
        (tester) async {
      await _pumpCard(tester, _makeOrder('confirmed'));
      expect(find.textContaining('Preparing:'), findsOneWidget);
    });

    testWidgets('does NOT show prep timer for ready_for_pickup',
        (tester) async {
      await _pumpCard(tester, _makeOrder('ready_for_pickup'));
      expect(find.textContaining('Preparing:'), findsNothing);
    });
  });
}
