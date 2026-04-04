import '../../restaurants/models/restaurant_model.dart';

class CartItem {
  final MenuItemModel menuItem;
  final int quantity;
  const CartItem({required this.menuItem, required this.quantity});
  CartItem copyWith({int? quantity}) =>
      CartItem(menuItem: menuItem, quantity: quantity ?? this.quantity);
  double get subtotal => menuItem.price * quantity;
}
