import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart_item.dart';
import '../../restaurants/models/restaurant_model.dart';

class CartState {
  final List<CartItem> items;
  final String? restaurantId;
  const CartState({this.items = const [], this.restaurantId});
  double get subtotal => items.fold(0, (s, i) => s + i.subtotal);
  int get totalItems => items.fold(0, (s, i) => s + i.quantity);
  CartState copyWith({List<CartItem>? items, String? restaurantId}) =>
      CartState(
          items: items ?? this.items,
          restaurantId: restaurantId ?? this.restaurantId);
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  /// Returns false if item is unavailable or from a different restaurant.
  bool addItem(
    MenuItemModel item,
    String restaurantId, {
    List<SelectedModifier> selectedModifiers = const [],
  }) {
    // Defence-in-depth: never add unavailable items to cart
    if (!item.available) return false;
    if (state.restaurantId != null && state.restaurantId != restaurantId) {
      return false;
    }

    final newCartItem = CartItem(
      menuItem: item,
      quantity: 1,
      selectedModifiers: selectedModifiers,
    );
    final key = newCartItem.cartKey;
    final idx = state.items.indexWhere((i) => i.cartKey == key);
    final updated = [...state.items];

    if (idx >= 0) {
      updated[idx] = updated[idx].copyWith(quantity: updated[idx].quantity + 1);
    } else {
      updated.add(newCartItem);
    }
    state = state.copyWith(items: updated, restaurantId: restaurantId);
    return true;
  }

  void clearAndAdd(
    MenuItemModel item,
    String restaurantId, {
    List<SelectedModifier> selectedModifiers = const [],
  }) {
    state = CartState(
      items: [
        CartItem(
          menuItem: item,
          quantity: 1,
          selectedModifiers: selectedModifiers,
        )
      ],
      restaurantId: restaurantId,
    );
  }

  void updateQuantity(String cartKey, int qty) {
    if (qty <= 0) {
      final updated = state.items.where((i) => i.cartKey != cartKey).toList();
      state = CartState(
          items: updated,
          restaurantId: updated.isEmpty ? null : state.restaurantId);
      return;
    }
    state = state.copyWith(
        items: state.items
            .map((i) => i.cartKey == cartKey ? i.copyWith(quantity: qty) : i)
            .toList());
  }

  void clear() => state = const CartState();
}

final cartProvider =
    StateNotifierProvider<CartNotifier, CartState>((_) => CartNotifier());
