// Tests for the full rider delivery flow:
//
//   delivery:request received
//     → Accept / Decline
//     → Active delivery card shown (Navigate to Restaurant)
//     → Confirm Pickup (→ Navigate to Customer)
//     → Confirm Delivery (→ back to idle)
//
// All network calls are intercepted via FakeRiderService / FakeSecureStorage
// so no real HTTP or FlutterSecureStorage calls are made.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:food_delivery_rider/features/delivery/screens/home_screen.dart';
import 'package:food_delivery_rider/features/delivery/services/rider_service.dart';
import 'package:food_delivery_rider/core/network/dio_client.dart';
import 'package:food_delivery_rider/core/storage/secure_storage.dart';
import 'package:food_delivery_rider/features/auth/providers/auth_provider.dart';
import 'package:food_delivery_rider/features/auth/services/auth_service.dart';
import 'package:food_delivery_rider/features/notifications/fcm_service.dart';

// ── Fake DioClient ────────────────────────────────────────────────────────────

class _FakeDioClient extends DioClient {
  _FakeDioClient() : super();
}

// ── Fake SecureStorageService ─────────────────────────────────────────────────
// Overrides every method so FlutterSecureStorage is never touched in tests.

class FakeSecureStorage extends SecureStorageService {
  bool _available = false;

  @override
  Future<String?> getJwt() async => null; // null → no socket connect attempt

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokens(
      {required String jwt, required String refreshToken}) async {}

  @override
  Future<void> clearTokens() async {}

  @override
  Future<bool> getAvailability() async => _available;

  @override
  Future<void> saveAvailability(bool value) async {
    _available = value;
  }
}

// ── Fake AuthService ──────────────────────────────────────────────────────────

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(_FakeDioClient(), FakeSecureStorage());

  @override
  Future<bool> isLoggedIn() async => true;

  @override
  Future<void> logout() async {}
}

// ── Fake AuthNotifier ─────────────────────────────────────────────────────────

class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier() : super(_FakeAuthService());
}

// ── Fake RiderService ─────────────────────────────────────────────────────────

class FakeRiderService extends RiderService {
  int acceptCallCount = 0;
  int declineCallCount = 0;
  int pickupCallCount = 0;
  int deliverCallCount = 0;

  String? lastAcceptedOrderId;
  String? lastPickupOrderId;
  String? lastDeliverOrderId;

  final Map<String, dynamic>? _navData;

  FakeRiderService({Map<String, dynamic>? navData})
      : _navData = navData,
        super(_FakeDioClient());

  @override
  Future<Map<String, dynamic>?> acceptDelivery(String orderId) async {
    acceptCallCount++;
    lastAcceptedOrderId = orderId;
    return _navData ??
        {
          'navigation': {
            'restaurant': {'latitude': 9.03, 'longitude': 38.74},
            'delivery': {'latitude': 9.05, 'longitude': 38.76},
          },
        };
  }

  @override
  Future<void> declineDelivery(String orderId) async {
    declineCallCount++;
  }

  @override
  Future<void> confirmPickup(String orderId) async {
    pickupCallCount++;
    lastPickupOrderId = orderId;
  }

  @override
  Future<void> confirmDelivery(String orderId) async {
    deliverCallCount++;
    lastDeliverOrderId = orderId;
  }

  @override
  Future<void> setAvailability(String availability) async {}

  @override
  Future<void> updateLocation(
      double lat, double lon, String availability) async {}

  @override
  Future<Map<String, dynamic>?> getPendingInvitation() async => null;
}

// ── Helper: build the RiderHomeScreen with fakes injected ────────────────────

Widget _buildRiderHome({
  FakeRiderService? riderService,
  FakeSecureStorage? storage,
}) {
  final svc = riderService ?? FakeRiderService();
  final store = storage ?? FakeSecureStorage();

  return ProviderScope(
    overrides: [
      riderServiceProvider.overrideWithValue(svc),
      secureStorageProvider.overrideWithValue(store),
      authProvider.overrideWith((_) => FakeAuthNotifier()),
    ],
    child: const MaterialApp(
      home: RiderHomeScreen(),
    ),
  );
}

// ── Fake delivery request payload ─────────────────────────────────────────────

const _fakeRequest = {
  'orderId': 'order-uuid-1234',
  'restaurantName': 'Pizza Palace',
  'customerAddress': '123 Main St',
  'deliveryFee': 60.0,
  'estimatedDistance': 3.5,
  'expiresAt': '2099-01-01T00:00:00.000Z',
};

// ── Pump helper ───────────────────────────────────────────────────────────────
// Uses pump() with a short duration instead of pumpAndSettle() to avoid
// hanging on the FlutterMap tile requests (which are real HTTP calls that
// fail in the test environment and leave pending timers).

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    onDeliveryRequestReceived = null;
    pendingDeliveryRequest = null;
  });

  tearDown(() {
    onDeliveryRequestReceived = null;
    pendingDeliveryRequest = null;
  });

  // ── Idle state ─────────────────────────────────────────────────────────────
  group('RiderHomeScreen — idle state', () {
    testWidgets('renders Rider Dashboard AppBar', (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      expect(find.text('Rider Dashboard'), findsOneWidget);
    });

    testWidgets('shows availability toggle switch', (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('shows offline empty state when not available', (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      expect(find.text("You're offline"), findsOneWidget);
    });

    testWidgets('no delivery request card shown initially', (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      expect(find.text('New Delivery Request'), findsNothing);
    });

    testWidgets('no active delivery card shown initially', (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      expect(find.text('Active Delivery'), findsNothing);
    });
  });

  // ── Delivery request card ──────────────────────────────────────────────────
  group('RiderHomeScreen — delivery request received', () {
    testWidgets('delivery request card shows restaurant name and fee',
        (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      expect(find.text('New Delivery Request'), findsOneWidget);
      expect(find.text('Pizza Palace'), findsOneWidget);
      expect(find.textContaining('60'), findsOneWidget);
      expect(find.textContaining('3.5'), findsOneWidget);
    });

    testWidgets('delivery request card shows Accept and Decline buttons',
        (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('tapping Decline calls declineDelivery and hides card',
        (tester) async {
      final svc = FakeRiderService();
      await tester.pumpWidget(_buildRiderHome(riderService: svc));
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      await tester.tap(find.text('Decline'));
      await tester.pump();

      expect(svc.declineCallCount, 1);
      expect(find.text('New Delivery Request'), findsNothing);
    });
  });

  // ── Accept → active delivery ───────────────────────────────────────────────
  group('RiderHomeScreen — accept delivery', () {
    testWidgets('tapping Accept calls acceptDelivery with correct orderId',
        (tester) async {
      final svc = FakeRiderService();
      await tester.pumpWidget(_buildRiderHome(riderService: svc));
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(svc.acceptCallCount, 1);
      expect(svc.lastAcceptedOrderId, 'order-uuid-1234');
    });

    testWidgets('after Accept, delivery request card disappears',
        (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.text('New Delivery Request'), findsNothing);
    });

    testWidgets('after Accept, Active Delivery card appears', (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.text('Active Delivery'), findsOneWidget);
    });

    testWidgets('after Accept, Navigate to Restaurant button is shown',
        (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.text('Navigate to Restaurant'), findsOneWidget);
    });

    testWidgets('after Accept, Confirm Pickup button is shown', (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.text('Confirm Pickup'), findsOneWidget);
    });

    testWidgets('after Accept, Navigate to Customer is NOT yet shown',
        (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.text('Navigate to Customer'), findsNothing);
    });

    testWidgets('order id prefix shown in active delivery header',
        (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();

      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await _settle(tester);

      // 'order-uuid-1234'.substring(0,8).toUpperCase() = 'ORDER-UU'
      expect(find.textContaining('ORDER-UU'), findsOneWidget);
    });
  });

  // ── Confirm Pickup ─────────────────────────────────────────────────────────
  group('RiderHomeScreen — confirm pickup', () {
    // Helper: pump to the post-accept state
    Future<FakeRiderService> _acceptAndGetSvc(WidgetTester tester) async {
      final svc = FakeRiderService();
      await tester.pumpWidget(_buildRiderHome(riderService: svc));
      await tester.pump();
      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();
      await tester.tap(find.text('Accept'));
      await _settle(tester);
      return svc;
    }

    testWidgets('tapping Confirm Pickup calls confirmPickup', (tester) async {
      final svc = await _acceptAndGetSvc(tester);

      await tester.tap(find.text('Confirm Pickup'));
      await _settle(tester);

      expect(svc.pickupCallCount, 1);
      expect(svc.lastPickupOrderId, 'order-uuid-1234');
    });

    testWidgets('after Confirm Pickup, Navigate to Customer appears',
        (tester) async {
      await _acceptAndGetSvc(tester);

      await tester.tap(find.text('Confirm Pickup'));
      await _settle(tester);

      expect(find.text('Navigate to Customer'), findsOneWidget);
    });

    testWidgets('after Confirm Pickup, Navigate to Restaurant disappears',
        (tester) async {
      await _acceptAndGetSvc(tester);

      await tester.tap(find.text('Confirm Pickup'));
      await _settle(tester);

      expect(find.text('Navigate to Restaurant'), findsNothing);
    });

    testWidgets('after Confirm Pickup, Confirm Delivery button appears',
        (tester) async {
      await _acceptAndGetSvc(tester);

      await tester.tap(find.text('Confirm Pickup'));
      await _settle(tester);

      expect(find.text('Confirm Delivery'), findsOneWidget);
    });

    testWidgets('after Confirm Pickup, Confirm Pickup button disappears',
        (tester) async {
      await _acceptAndGetSvc(tester);

      await tester.tap(find.text('Confirm Pickup'));
      await _settle(tester);

      expect(find.text('Confirm Pickup'), findsNothing);
    });
  });

  // ── Confirm Delivery ───────────────────────────────────────────────────────
  group('RiderHomeScreen — confirm delivery', () {
    Future<FakeRiderService> _pickupAndGetSvc(WidgetTester tester) async {
      final svc = FakeRiderService();
      await tester.pumpWidget(_buildRiderHome(riderService: svc));
      await tester.pump();
      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();
      await tester.tap(find.text('Accept'));
      await _settle(tester);
      await tester.tap(find.text('Confirm Pickup'));
      await _settle(tester);
      return svc;
    }

    testWidgets('tapping Confirm Delivery calls confirmDelivery',
        (tester) async {
      final svc = await _pickupAndGetSvc(tester);

      await tester.tap(find.text('Confirm Delivery'));
      await _settle(tester);

      expect(svc.deliverCallCount, 1);
      expect(svc.lastDeliverOrderId, 'order-uuid-1234');
    });

    testWidgets('after Confirm Delivery, Active Delivery card disappears',
        (tester) async {
      await _pickupAndGetSvc(tester);

      await tester.tap(find.text('Confirm Delivery'));
      await _settle(tester);

      expect(find.text('Active Delivery'), findsNothing);
    });

    testWidgets('after Confirm Delivery, rider returns to idle state',
        (tester) async {
      await _pickupAndGetSvc(tester);

      await tester.tap(find.text('Confirm Delivery'));
      await _settle(tester);

      expect(find.text("You're offline"), findsOneWidget);
    });
  });

  // ── Navigation button fallbacks ────────────────────────────────────────────
  group('RiderHomeScreen — navigation button fallbacks', () {
    testWidgets('shows fallback text when restaurant coords are null',
        (tester) async {
      final svc = FakeRiderService(
        navData: {
          'navigation': {
            'restaurant': null,
            'delivery': {'latitude': 9.05, 'longitude': 38.76},
          },
        },
      );
      await tester.pumpWidget(_buildRiderHome(riderService: svc));
      await tester.pump();
      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();
      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.text('Restaurant location unavailable'), findsOneWidget);
    });

    testWidgets(
        'shows fallback text when customer coords are null after pickup',
        (tester) async {
      final svc = FakeRiderService(
        navData: {
          'navigation': {
            'restaurant': {'latitude': 9.03, 'longitude': 38.74},
            'delivery': null,
          },
        },
      );
      await tester.pumpWidget(_buildRiderHome(riderService: svc));
      await tester.pump();
      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();
      await tester.tap(find.text('Accept'));
      await _settle(tester);
      await tester.tap(find.text('Confirm Pickup'));
      await _settle(tester);

      expect(find.text('Customer location unavailable'), findsOneWidget);
    });
  });

  // ── Chat button ────────────────────────────────────────────────────────────
  group('RiderHomeScreen — chat button', () {
    testWidgets('chat icon appears in active delivery header', (tester) async {
      await tester.pumpWidget(_buildRiderHome());
      await tester.pump();
      onDeliveryRequestReceived?.call(_fakeRequest);
      await tester.pump();
      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });
  });
}
