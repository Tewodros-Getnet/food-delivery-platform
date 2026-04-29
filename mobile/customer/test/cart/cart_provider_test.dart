import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:food_delivery_customer/features/cart/providers/cart_provider.dart';
import 'package:food_delivery_customer/features/restaurants/models/restaurant_model.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

MenuItemModel _item({
  String id = 'item-1',
  String name = 'Burger',
  double price = 50.0,
  String restaurantId = 'rest-1',
}) =>
    MenuItemModel(
      id: id,
      restaurantId: restaurantId,
      name: name,
      price: price,
      imageUrl: 'https://example.com/img.jpg',
      available: true,
    );

CartNotifier _notifier() => CartNotifier();

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('CartNotifier — initial state', () {
    test('starts empty', () {
      final n = _notifier();
      expect(n.state.items, isEmpty);
      expect(n.state.restaurantId, isNull);
      expect(n.state.subtotal, 0.0);
      expect(n.state.totalItems, 0);
    });
  });

  group('CartNotifier — addItem', () {
    test('adds item successfully', () {
      final n = _notifier();
      final result = n.addItem(_item(), 'rest-1');

      expect(result, isTrue);
      expect(n.state.items.length, 1);
      expect(n.state.items.first.menuItem.name, 'Burger');
      expect(n.state.restaurantId, 'rest-1');
    });

    test('increments quantity when same item added twice', () {
      final n = _notifier();
      n.addItem(_item(), 'rest-1');
      n.addItem(_item(), 'rest-1');

      expect(n.state.items.length, 1);
      expect(n.state.items.first.quantity, 2);
    });

    test('returns false when adding item from different restaurant', () {
      final n = _notifier();
      n.addItem(_item(restaurantId: 'rest-1'), 'rest-1');
      final result = n.addItem(_item(restaurantId: 'rest-2'), 'rest-2');

      expect(result, isFalse);
      expect(n.state.items.length, 1); // original item unchanged
    });

    test('does not add unavailable items', () {
      final n = _notifier();
      final unavailable = MenuItemModel(
        id: 'item-x',
        restaurantId: 'rest-1',
        name: 'Sold Out',
        price: 30.0,
        imageUrl: '',
        available: false,
      );
      final result = n.addItem(unavailable, 'rest-1');

      expect(result, isFalse);
      expect(n.state.items, isEmpty);
    });

    test('calculates subtotal correctly', () {
      final n = _notifier();
      n.addItem(_item(price: 50.0), 'rest-1');
      n.addItem(_item(price: 50.0), 'rest-1'); // qty = 2

      expect(n.state.subtotal, 100.0);
    });

    test('totalItems counts quantities', () {
      final n = _notifier();
      n.addItem(_item(id: 'item-1'), 'rest-1');
      n.addItem(_item(id: 'item-1'), 'rest-1'); // qty = 2
      n.addItem(_item(id: 'item-2', name: 'Fries'), 'rest-1'); // qty = 1

      expect(n.state.totalItems, 3);
    });
  });

  group('CartNotifier — updateQuantity', () {
    test('updates quantity correctly', () {
      final n = _notifier();
      n.addItem(_item(), 'rest-1');
      final key = n.state.items.first.cartKey;

      n.updateQuantity(key, 5);
      expect(n.state.items.first.quantity, 5);
    });

    test('removes item when quantity set to 0', () {
      final n = _notifier();
      n.addItem(_item(), 'rest-1');
      final key = n.state.items.first.cartKey;

      n.updateQuantity(key, 0);
      expect(n.state.items, isEmpty);
    });

    test('clears restaurantId when last item removed', () {
      final n = _notifier();
      n.addItem(_item(), 'rest-1');
      final key = n.state.items.first.cartKey;

      n.updateQuantity(key, 0);
      expect(n.state.restaurantId, isNull);
    });

    test('removes item when quantity set to negative', () {
      final n = _notifier();
      n.addItem(_item(), 'rest-1');
      final key = n.state.items.first.cartKey;

      n.updateQuantity(key, -1);
      expect(n.state.items, isEmpty);
    });
  });

  group('CartNotifier — clear', () {
    test('clears all items', () {
      final n = _notifier();
      n.addItem(_item(id: 'item-1'), 'rest-1');
      n.addItem(_item(id: 'item-2', name: 'Fries'), 'rest-1');

      n.clear();
      expect(n.state.items, isEmpty);
      expect(n.state.restaurantId, isNull);
      expect(n.state.subtotal, 0.0);
    });
  });

  group('CartNotifier — clearAndAdd', () {
    test('replaces existing cart with new item', () {
      final n = _notifier();
      n.addItem(_item(id: 'item-1', restaurantId: 'rest-1'), 'rest-1');

      n.clearAndAdd(
          _item(id: 'item-2', name: 'Pizza', restaurantId: 'rest-2'), 'rest-2');

      expect(n.state.items.length, 1);
      expect(n.state.items.first.menuItem.name, 'Pizza');
      expect(n.state.restaurantId, 'rest-2');
    });
  });

  group('CartItem — cartKey', () {
    test('same item without modifiers has same key', () {
      final n = _notifier();
      n.addItem(_item(), 'rest-1');
      n.addItem(_item(), 'rest-1');

      // Should be merged into one item with qty 2
      expect(n.state.items.length, 1);
      expect(n.state.items.first.quantity, 2);
    });
  });
}
