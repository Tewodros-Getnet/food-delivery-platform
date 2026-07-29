// Feature: menu-availability-toggle
// Task 5.1 — Property 4: Optimistic revert on error
//
// Widget test for MenuScreen:
//   - Stub MenuService.toggleAvailability to throw
//   - Tap the Switch
//   - Assert the Switch value reverts to its original state
//   - Assert a SnackBar with "Failed to update availability" is shown

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:food_delivery_restaurant/features/menu/services/menu_service.dart';
import 'package:food_delivery_restaurant/features/menu/screens/menu_screen.dart';
import 'package:food_delivery_restaurant/core/network/dio_client.dart';

// ── Fake helpers ──────────────────────────────────────────────────────────────

/// A [DioClient] stub that is never actually used — we override
/// [menuServiceProvider] so the real DioClient is never constructed.
class _FakeDioClient extends DioClient {
  _FakeDioClient() : super();
}

/// Stub [MenuService] that lets tests control what [getItems] returns
/// and whether [toggleAvailability] succeeds or throws.
class FakeMenuService extends MenuService {
  final List<dynamic> items;
  final bool toggleShouldThrow;
  final String? toggleThrowMessage;

  /// If non-null, [toggleAvailability] returns this map on success.
  final Map<String, dynamic>? toggleResult;

  int toggleCallCount = 0;
  String? lastToggledId;

  FakeMenuService({
    required this.items,
    this.toggleShouldThrow = false,
    this.toggleThrowMessage,
    this.toggleResult,
  }) : super(_FakeDioClient());

  @override
  Future<List<dynamic>> getItems(String restaurantId) async => items;

  @override
  Future<Map<String, dynamic>> toggleAvailability(String id) async {
    toggleCallCount++;
    lastToggledId = id;
    if (toggleShouldThrow) {
      throw Exception(toggleThrowMessage ?? 'Network error');
    }
    // Return the provided result, or flip the available flag of the matching item
    if (toggleResult != null) return toggleResult!;
    final item = items.firstWhere(
      (e) => (e as Map<String, dynamic>)['id'] == id,
      orElse: () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    return {...item, 'available': !(item['available'] as bool? ?? true)};
  }

  @override
  Future<void> createItem(
      String restaurantId, Map<String, dynamic> data) async {}

  @override
  Future<void> updateItem(String id, Map<String, dynamic> data) async {}

  @override
  Future<void> deleteItem(String id) async {}

  @override
  Future<Map<String, dynamic>> getItemById(String id) async => {};

  @override
  Future<Map<String, dynamic>> updateModifiers(
          String id, List<Map<String, dynamic>> modifiers) async =>
      {};
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Map<String, dynamic> _makeItem({
  String id = 'item-1',
  String name = 'Test Item',
  bool available = true,
}) =>
    {
      'id': id,
      'name': name,
      'description': 'A test item',
      'price': 50.0,
      'category': 'Mains',
      'image_url': 'https://example.com/image.jpg',
      'available': available,
      'modifiers': <dynamic>[],
    };

Widget _buildScreen({
  required FakeMenuService fakeMenuService,
  String restaurantId = 'rest-1',
}) {
  return ProviderScope(
    overrides: [
      menuServiceProvider.overrideWithValue(fakeMenuService),
    ],
    child: MaterialApp(
      home: MenuScreen(restaurantId: restaurantId),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Property 4: Optimistic revert on error
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group(
      'Feature: menu-availability-toggle, Property 4: Optimistic revert on error',
      () {
    testWidgets(
      'when toggleAvailability throws, Switch reverts to original state (true) and SnackBar is shown',
      (tester) async {
        final item = _makeItem(available: true);
        final fakeService = FakeMenuService(
          items: [item],
          toggleShouldThrow: true,
          toggleThrowMessage: 'Network error',
        );

        await tester.pumpWidget(_buildScreen(fakeMenuService: fakeService));
        await tester.pumpAndSettle();

        // Find the Switch — it should be ON (available = true)
        final switchFinder = find.byType(Switch);
        expect(switchFinder, findsOneWidget);
        expect(tester.widget<Switch>(switchFinder).value, isTrue);

        // Tap the Switch — triggers optimistic flip + async API call
        await tester.tap(switchFinder);
        await tester.pump(); // process the tap synchronously

        // Optimistic update: Switch flips to false immediately
        expect(tester.widget<Switch>(switchFinder).value, isFalse);
        // Switch is disabled while in-flight
        expect(tester.widget<Switch>(switchFinder).onChanged, isNull);

        // Let the future complete (throws)
        await tester.pumpAndSettle();

        // After error: Switch must revert to original value (true)
        expect(tester.widget<Switch>(switchFinder).value, isTrue);

        // SnackBar with the correct message must be visible
        expect(find.text('Failed to update availability'), findsOneWidget);
      },
    );

    testWidgets(
      'when toggleAvailability throws on an unavailable item, Switch reverts to false',
      (tester) async {
        final item = _makeItem(available: false);
        final fakeService = FakeMenuService(
          items: [item],
          toggleShouldThrow: true,
          toggleThrowMessage: 'Server error',
        );

        await tester.pumpWidget(_buildScreen(fakeMenuService: fakeService));
        await tester.pumpAndSettle();

        final switchFinder = find.byType(Switch);
        expect(tester.widget<Switch>(switchFinder).value, isFalse);

        await tester.tap(switchFinder);
        await tester.pump();

        // Optimistic flip to true
        expect(tester.widget<Switch>(switchFinder).value, isTrue);

        await tester.pumpAndSettle();

        // Reverted back to false
        expect(tester.widget<Switch>(switchFinder).value, isFalse);
        expect(find.text('Failed to update availability'), findsOneWidget);
      },
    );

    testWidgets(
      'when toggleAvailability succeeds, Switch stays at new value (no revert)',
      (tester) async {
        final item = _makeItem(available: true);
        final updatedItem = _makeItem(available: false);
        final fakeService = FakeMenuService(
          items: [item],
          toggleShouldThrow: false,
          toggleResult: updatedItem,
        );

        await tester.pumpWidget(_buildScreen(fakeMenuService: fakeService));
        await tester.pumpAndSettle();

        final switchFinder = find.byType(Switch);
        expect(tester.widget<Switch>(switchFinder).value, isTrue);

        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        // Switch stays at the new value (false) — no revert
        expect(tester.widget<Switch>(switchFinder).value, isFalse);

        // No error SnackBar
        expect(find.text('Failed to update availability'), findsNothing);
      },
    );

    testWidgets(
      'toggleAvailability is called exactly once per tap',
      (tester) async {
        final item = _makeItem(available: true);
        final fakeService = FakeMenuService(
          items: [item],
          toggleShouldThrow: false,
        );

        await tester.pumpWidget(_buildScreen(fakeMenuService: fakeService));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(fakeService.toggleCallCount, 1);
        expect(fakeService.lastToggledId, 'item-1');
      },
    );

    testWidgets(
      'Switch is disabled (onChanged == null) while API call is in-flight',
      (tester) async {
        // Use a slow future to keep the in-flight state visible
        final item = _makeItem(available: true);
        final fakeService = FakeMenuService(
          items: [item],
          toggleShouldThrow: false,
        );

        await tester.pumpWidget(_buildScreen(fakeMenuService: fakeService));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Switch));
        await tester.pump(); // one frame — future not yet resolved

        // Switch must be disabled while in-flight
        expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);

        await tester.pumpAndSettle();

        // After completion, Switch is re-enabled
        expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
      },
    );
  });
}
