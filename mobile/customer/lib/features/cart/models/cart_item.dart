import '../../restaurants/models/restaurant_model.dart';

class SelectedModifier {
  final String group;
  final String option;
  final double price;

  const SelectedModifier({
    required this.group,
    required this.option,
    required this.price,
  });

  Map<String, dynamic> toJson() => {
        'group': group,
        'option': option,
        'price': price,
      };
}

class CartItem {
  final MenuItemModel menuItem;
  final int quantity;
  final List<SelectedModifier> selectedModifiers;

  const CartItem({
    required this.menuItem,
    required this.quantity,
    this.selectedModifiers = const [],
  });

  CartItem copyWith(
          {int? quantity, List<SelectedModifier>? selectedModifiers}) =>
      CartItem(
        menuItem: menuItem,
        quantity: quantity ?? this.quantity,
        selectedModifiers: selectedModifiers ?? this.selectedModifiers,
      );

  double get modifiersPrice =>
      selectedModifiers.fold(0.0, (sum, m) => sum + m.price);

  double get unitPrice => menuItem.price + modifiersPrice;

  double get subtotal => unitPrice * quantity;

  /// Unique key combining item ID + selected modifiers for cart deduplication
  String get cartKey {
    if (selectedModifiers.isEmpty) return menuItem.id;
    final modKey =
        selectedModifiers.map((m) => '${m.group}:${m.option}').join(',');
    return '${menuItem.id}|$modKey';
  }
}
