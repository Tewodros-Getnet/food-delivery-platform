// Tests for PendingAcceptanceOrderCard.
//
// NOTE: CountdownTimer uses Timer.periodic, so pumpAndSettle() hangs.
// All tests use pump() + pump(duration) instead.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:food_delivery_restaurant/features/orders/models/order_model.dart';
import 'package:food_delivery_restaurant/features/orders/services/order_service.dart';
import 'package:food_delivery_restaurant/features/orders/widgets/pending_acceptance_order_card.dart';
import 'package:food_delivery_restaurant/core/network/dio_client.dart';

// Fake helpers

class _FakeDioClient extends DioClient {
  _FakeDioClient() : super();
}

class FakeOrderService extends OrderService {
  bool shouldThrow;
  String? throwMessage;
  int acceptCallCount = 0;
  int rejectCallCount = 0;
  String? lastAcceptedId;
  String? lastRejectedReason;

  FakeOrderService({this.shouldThrow = false, this.throwMessage})
      : super(_FakeDioClient());

  @override
  Future<void> acceptOrder(String orderId,
      {int? estimatedPrepTimeMinutes}) async {
    acceptCallCount++;
    lastAcceptedId = orderId;
    if (shouldThrow) throw Exception(throwMessage ?? 'API error');
  }

  @override
  Future<void> rejectOrder(String orderId, String reason) async {
    rejectCallCount++;
    lastRejectedReason = reason;
    if (shouldThrow) throw Exception(throwMessage ?? 'API error');
  }

  @override
  Future<List<OrderModel>> getOrders() async => [];

  @override
  Future<void> markReady(String orderId, {int? prepTime}) async {}

  @override
  Future<void> cancelOrder(String orderId, String reason) async {}
}

OrderModel _makeOrder({DateTime? deadline}) => OrderModel(
      id: 'aaaabbbb-cccc-dddd-eeee-ffffffffffff',
      restaurantId: 'rest-1',
      status: 'pending_acceptance',
      subtotal: 90.0,
      deliveryFee: 10.0,
      total: 100.0,
      createdAt: DateTime(2026, 4, 1, 12, 0),
      acceptanceDeadline: deadline,
    );

Future<FakeOrderService> _pumpCard(
  WidgetTester tester,
  OrderModel order, {
  bool shouldThrow = false,
  String? throwMessage,
  VoidCallback? onAccepted,
  VoidCallback? onRejected,
}) async {
  final svc =
      FakeOrderService(shouldThrow: shouldThrow, throwMessage: throwMessage);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [orderServiceProvider.overrideWithValue(svc)],
      child: MaterialApp(
        home: Scaffold(
          body: PendingAcceptanceOrderCard(
            order: order,
            onAccepted: onAccepted ?? () {},
            onRejected: onRejected ?? () {},
          ),
        ),
      ),
    ),
  );
  return svc;
}

// Settle helper that avoids pumpAndSettle (CountdownTimer has periodic timer)
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('PendingAcceptanceOrderCard - UI structure', () {
    testWidgets('shows order id prefix', (tester) async {
      await _pumpCard(tester, _makeOrder());
      expect(find.textContaining('aaaabbbb'), findsOneWidget);
    });

    testWidgets('shows total amount', (tester) async {
      await _pumpCard(tester, _makeOrder());
      expect(find.textContaining('100.00'), findsOneWidget);
    });

    testWidgets('shows Awaiting your response badge', (tester) async {
      await _pumpCard(tester, _makeOrder());
      expect(find.text('Awaiting your response'), findsOneWidget);
    });

    testWidgets('shows Accept and Reject buttons for non-expired order',
        (tester) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      await _pumpCard(tester, _makeOrder(deadline: deadline));
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('shows countdown MM:SS when deadline is set', (tester) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      await _pumpCard(tester, _makeOrder(deadline: deadline));
      // CountdownTimer renders "02:59" style text
      expect(find.textContaining(':'), findsWidgets);
    });
  });

  group('PendingAcceptanceOrderCard - expired order', () {
    testWidgets('hides Accept and Reject buttons when deadline has passed',
        (tester) async {
      final expired = DateTime.now().subtract(const Duration(minutes: 1));
      await _pumpCard(tester, _makeOrder(deadline: expired));
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('shows expiry message when deadline has passed',
        (tester) async {
      final expired = DateTime.now().subtract(const Duration(minutes: 1));
      await _pumpCard(tester, _makeOrder(deadline: expired));
      expect(find.textContaining('expired'), findsOneWidget);
    });
  });

  group('PendingAcceptanceOrderCard - accept flow', () {
    testWidgets('tapping Accept calls acceptOrder with correct id',
        (tester) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      final svc = await _pumpCard(tester, _makeOrder(deadline: deadline));

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(svc.acceptCallCount, 1);
      expect(svc.lastAcceptedId, 'aaaabbbb-cccc-dddd-eeee-ffffffffffff');
    });

    testWidgets('onAccepted callback fires after successful accept',
        (tester) async {
      bool fired = false;
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      await _pumpCard(
        tester,
        _makeOrder(deadline: deadline),
        onAccepted: () => fired = true,
      );

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(fired, isTrue);
    });

    testWidgets('shows success snackbar after accepting', (tester) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      await _pumpCard(tester, _makeOrder(deadline: deadline));

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.textContaining('accepted'), findsOneWidget);
    });

    testWidgets('shows error snackbar when accept fails', (tester) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      await _pumpCard(
        tester,
        _makeOrder(deadline: deadline),
        shouldThrow: true,
        throwMessage: 'Order not found',
      );

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.textContaining('Failed to accept'), findsOneWidget);
    });
  });

  group('PendingAcceptanceOrderCard - reject flow', () {
    testWidgets('tapping Reject opens the RejectOrderDialog', (tester) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      await _pumpCard(tester, _makeOrder(deadline: deadline));

      await tester.tap(find.text('Reject'));
      await _settle(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Reject dialog has a text field for the reason',
        (tester) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      await _pumpCard(tester, _makeOrder(deadline: deadline));

      await tester.tap(find.text('Reject'));
      await _settle(tester);

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Reject Order confirm button is disabled when reason is empty',
        (tester) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      await _pumpCard(tester, _makeOrder(deadline: deadline));

      await tester.tap(find.text('Reject'));
      await _settle(tester);

      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Reject Order'),
      );
      expect(confirmBtn.onPressed, isNull);
    });

    testWidgets('Reject Order button enables after typing a reason',
        (tester) async {
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      await _pumpCard(tester, _makeOrder(deadline: deadline));

      await tester.tap(find.text('Reject'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'Kitchen closed');
      await tester.pump();

      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Reject Order'),
      );
      expect(confirmBtn.onPressed, isNotNull);
    });

    testWidgets('submitting rejection calls rejectOrder and fires onRejected',
        (tester) async {
      bool fired = false;
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      final svc = await _pumpCard(
        tester,
        _makeOrder(deadline: deadline),
        onRejected: () => fired = true,
      );

      await tester.tap(find.text('Reject'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'Item unavailable');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Reject Order'));
      await _settle(tester);

      expect(svc.rejectCallCount, 1);
      expect(svc.lastRejectedReason, 'Item unavailable');
      expect(fired, isTrue);
    });
  });
}
