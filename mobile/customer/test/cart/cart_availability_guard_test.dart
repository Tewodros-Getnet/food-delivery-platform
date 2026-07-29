// Feature: menu-availability-toggle
// Task 5.2 — Property 5: Cart guard for unavailable items
//
// Unit test for CartNotifier.addItem:
//   - Call with a MenuItemModel where available: false
//   - Assert return value is false
//   - Assert cartProvider.state.items remains empty

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:food_delivery_customer/features/cart/providers/cart_provider.dart';
import 'package:food_delivery_customer/features/restaurants/models/restaurant_model.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

MenuItemModel _makeItem({
  String id = 'item-1',
  String restaurantId = 'rest-1',
  bool available = true,
}) =>
    MenuItemModel(
      id: id,
      restaurantId: restaurantId,
      name: 'Test Item',
      description: 'A test item',
      price: 50.0,
      category: 'Mains',
      imageUrl: 'https://example.com/image.jpg',
      available: available,
    );

// ═══════════════════════════════════════════════════════════════════════════
// Property 5: Cart guard for unavailable items
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('Property 5: Cart guard for unavailable items', () {
    test(
      'addItem with available=false returns false and cart remains empty',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final cart = container.read(cartProvider.notifier);
        final unavailableItem = _makeItem(available: false);

        final result = cart.addItem(unavailableItem, 'rest-1');

        expect(result, isFalse);
        expect(container.read(cartProvider).items, isEmpty);
      },
    );

    test(
      'addItem with available=true returns true and item is added',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final cart = container.read(cartProvider.notifier);
        final availableItem = _makeItem(available: true);

        final result = cart.addItem(availableItem, 'rest-1');

        expect(result, isTrue);
        expect(container.read(cartProvider).items, hasLength(1));
        expect(container.read(cartProvider).items.first.menuItem.id, 'item-1');
      },
    );

    test(
      'addItem with available=false does not change cart even when called multiple times',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final cart = container.read(cartProvider.notifier);
        final unavailableItem = _makeItem(available: false);

        // Call multiple times — cart must stay empty
        for (var i = 0; i < 5; i++) {
          final result = cart.addItem(unavailableItem, 'rest-1');
          expect(result, isFalse);
        }

        expect(container.read(cartProvider).items, isEmpty);
        expect(container.read(cartProvider).restaurantId, isNull);
      },
    );

    test(
      'addItem with available=false does not affect existing cart items',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final cart = container.read(cartProvider.notifier);

        // First add an available item
        final availableItem = _makeItem(id: 'item-1', available: true);
        cart.addItem(availableItem, 'rest-1');
        expect(container.read(cartProvider).items, hasLength(1));

        // Then try to add an unavailable item
        final unavailableItem = _makeItem(id: 'item-2', available: false);
        final result = cart.addItem(unavailableItem, 'rest-1');

        expect(result, isFalse);
        // Cart still has only the original item
        expect(container.read(cartProvider).items, hasLength(1));
        expect(container.read(cartProvider).items.first.menuItem.id, 'item-1');
      },
    );

    test(
      'addItem with available=false returns false regardless of restaurantId',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final cart = container.read(cartProvider.notifier);
        final unavailableItem = _makeItem(available: false);

        // Try with various restaurant IDs
        for (final restId in ['rest-1', 'rest-2', 'rest-3']) {
          final result = cart.addItem(unavailableItem, restId);
          expect(result, isFalse,
              reason: 'Should return false for restaurantId=$restId');
        }

        expect(container.read(cartProvider).items, isEmpty);
      },
    );
  });
}
