// ignore_for_file: invalid_use_of_protected_member

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:food_delivery_restaurant/features/orders/models/order_model.dart';
import 'package:food_delivery_restaurant/features/orders/screens/orders_screen.dart';
import 'package:food_delivery_restaurant/features/orders/services/order_service.dart';
import 'package:food_delivery_restaurant/core/network/dio_client.dart';

// ---------------------------------------------------------------------------
// Fake / stub helpers
// ---------------------------------------------------------------------------

/// A [DioClient] stub that is never actually used in tests — we override
/// [orderServiceProvider] so the real DioClient is never constructed.
class _FakeDioClient extends DioClient {
  _FakeDioClient() : super();
}

/// Stub [OrderService] that lets tests control whether [cancelOrder] succeeds
/// or throws.
class FakeOrderService extends OrderService {
  bool shouldThrow;
  String? throwMessage;
  int cancelCallCount = 0;
  String? lastCancelledOrderId;
  String? lastCancelledReason;

  FakeOrderService({this.shouldThrow = false, this.throwMessage})
      : super(_FakeDioClient());

  @override
  Future<void> cancelOrder(String orderId, String reason) async {
    cancelCallCount++;
    lastCancelledOrderId = orderId;
    lastCancelledReason = reason;
    if (shouldThrow) {
      throw Exception(throwMessage ?? 'API error');
    }
  }

  @override
  Future<List<OrderModel>> getOrders() async => [];

  @override
  Future<void> markReady(String orderId, {int? prepTime}) async {}
}

// ---------------------------------------------------------------------------
// Helper: build an [OrderModel] with a given status
// ---------------------------------------------------------------------------
OrderModel _makeOrder(String status) => OrderModel(
      id: 'aaaabbbb-cccc-dddd-eeee-ffffffffffff',
      restaurantId: 'rest-1',
      status: status,
      total: 100.0,
      createdAt: DateTime(2024, 1, 1, 12, 0),
    );

// ---------------------------------------------------------------------------
// Helper: pump an [_OrderCard] inside ProviderScope + MaterialApp
// ---------------------------------------------------------------------------
Future<FakeOrderService> _pumpOrderCard(
  WidgetTester tester,
  OrderModel order, {
  bool shouldThrow = false,
  String? throwMessage,
  VoidCallback? onCancelled,
  VoidCallback? onMarkReady,
}) async {
  final fakeService = FakeOrderService(
    shouldThrow: shouldThrow,
    throwMessage: throwMessage,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderServiceProvider.overrideWithValue(fakeService),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: OrderCardTestWrapper(
            order: order,
            onCancelled: onCancelled ?? () {},
            onMarkReady: onMarkReady ?? () {},
          ),
        ),
      ),
    ),
  );

  return fakeService;
}

// ---------------------------------------------------------------------------
// Property 6 — Cancel button visibility matches order status
//
// Tag: Feature: restaurant-order-cancellation,
//      Property 6: cancel button visibility matches order status
//
// Validates: Requirements 4.1, 4.6
// ---------------------------------------------------------------------------
void main() {
  group(
    'Feature: restaurant-order-cancellation, '
    'Property 6: cancel button visibility matches order status',
    () {
      const cancellableStatuses = {'confirmed', 'ready_for_pickup'};

      const allStatuses = [
        'confirmed',
        'ready_for_pickup',
        'rider_assigned',
        'picked_up',
        'delivered',
        'cancelled',
        'pending_payment',
        'payment_failed',
      ];

      for (final status in allStatuses) {
        testWidgets(
          'Cancel Order button is '
          '${cancellableStatuses.contains(status) ? "PRESENT" : "ABSENT"} '
          'for status "$status"',
          (tester) async {
            await _pumpOrderCard(tester, _makeOrder(status));

            final cancelButton = find.text('Cancel Order');

            if (cancellableStatuses.contains(status)) {
              expect(
                cancelButton,
                findsOneWidget,
                reason:
                    'Expected "Cancel Order" button to be present for status "$status"',
              );
            } else {
              expect(
                cancelButton,
                findsNothing,
                reason:
                    'Expected "Cancel Order" button to be absent for status "$status"',
              );
            }
          },
        );
      }
    },
  );

  // -------------------------------------------------------------------------
  // Property 7 — Successful cancellation removes order from active list
  //
  // Tag: Feature: restaurant-order-cancellation,
  //      Property 7: successful cancellation removes order from active list
  //
  // Validates: Requirements 4.4
  // -------------------------------------------------------------------------
  group(
    'Feature: restaurant-order-cancellation, '
    'Property 7: successful cancellation removes order from active list',
    () {
      testWidgets(
        'onCancelled callback is invoked after successful cancellation',
        (tester) async {
          bool callbackInvoked = false;
          final order = _makeOrder('confirmed');

          await _pumpOrderCard(
            tester,
            order,
            onCancelled: () => callbackInvoked = true,
          );

          // Tap "Cancel Order" to open the dialog
          await tester.tap(find.text('Cancel Order'));
          await tester.pumpAndSettle();

          // Select the first reason
          await tester.tap(find.text('Item unavailable'));
          await tester.pumpAndSettle();

          // Tap Confirm
          await tester.tap(find.text('Confirm'));
          await tester.pumpAndSettle();

          expect(
            callbackInvoked,
            isTrue,
            reason:
                'onCancelled callback must be invoked after successful cancellation '
                'so the parent can reload and remove the order from the active list',
          );
        },
      );

      testWidgets(
        'onCancelled callback is invoked for ready_for_pickup order',
        (tester) async {
          bool callbackInvoked = false;
          final order = _makeOrder('ready_for_pickup');

          await _pumpOrderCard(
            tester,
            order,
            onCancelled: () => callbackInvoked = true,
          );

          await tester.tap(find.text('Cancel Order'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Kitchen closed'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Confirm'));
          await tester.pumpAndSettle();

          expect(callbackInvoked, isTrue);
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Widget tests for the cancel dialog
  //
  // Tag: Feature: restaurant-order-cancellation (8.5)
  // Validates: Requirements 4.2, 4.3, 4.5
  // -------------------------------------------------------------------------
  group('Cancel dialog widget tests', () {
    testWidgets(
      'Tapping "Cancel Order" opens dialog with 5 radio options',
      (tester) async {
        await _pumpOrderCard(tester, _makeOrder('confirmed'));

        await tester.tap(find.text('Cancel Order'));
        await tester.pumpAndSettle();

        // Dialog title
        expect(find.text('Cancel Order'), findsWidgets);

        // All 5 predefined reasons
        expect(find.text('Item unavailable'), findsOneWidget);
        expect(find.text('Kitchen closed'), findsOneWidget);
        expect(find.text('Too busy'), findsOneWidget);
        expect(find.text('Ingredient ran out'), findsOneWidget);
        expect(find.text('Other'), findsOneWidget);
      },
    );

    testWidgets(
      '"Confirm" button is disabled until a reason is selected',
      (tester) async {
        await _pumpOrderCard(tester, _makeOrder('confirmed'));

        await tester.tap(find.text('Cancel Order'));
        await tester.pumpAndSettle();

        // Find the Confirm ElevatedButton and check its onPressed is null
        final confirmButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Confirm'),
        );
        expect(
          confirmButton.onPressed,
          isNull,
          reason: 'Confirm button must be disabled before a reason is selected',
        );
      },
    );

    testWidgets(
      '"Confirm" button becomes enabled after selecting a reason',
      (tester) async {
        await _pumpOrderCard(tester, _makeOrder('confirmed'));

        await tester.tap(find.text('Cancel Order'));
        await tester.pumpAndSettle();

        // Select a reason
        await tester.tap(find.text('Too busy'));
        await tester.pumpAndSettle();

        final confirmButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Confirm'),
        );
        expect(
          confirmButton.onPressed,
          isNotNull,
          reason: 'Confirm button must be enabled after a reason is selected',
        );
      },
    );

    testWidgets(
      'Error snackbar shown when API returns error; order card unchanged',
      (tester) async {
        const errorMsg = 'Order cannot be cancelled';
        await _pumpOrderCard(
          tester,
          _makeOrder('confirmed'),
          shouldThrow: true,
          throwMessage: errorMsg,
        );

        // Open dialog
        await tester.tap(find.text('Cancel Order'));
        await tester.pumpAndSettle();

        // Select a reason
        await tester.tap(find.text('Other'));
        await tester.pumpAndSettle();

        // Tap Confirm — this will throw
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();

        // Dialog should be dismissed
        expect(find.text('Item unavailable'), findsNothing);

        // Error snackbar should appear
        expect(
          find.textContaining(errorMsg),
          findsOneWidget,
          reason: 'Error snackbar must show the API error message',
        );

        // Order card should still be visible (unchanged)
        expect(find.text('Cancel Order'), findsOneWidget,
            reason: 'Order card must remain unchanged after an API error');
      },
    );
  });
}
