class OrderItemModel {
  final String id;
  final String menuItemId;
  final int quantity;
  final double unitPrice;
  final String itemName;
  final String? itemImageUrl;
  final List<Map<String, dynamic>> selectedModifiers;

  const OrderItemModel({
    required this.id,
    required this.menuItemId,
    required this.quantity,
    required this.unitPrice,
    required this.itemName,
    this.itemImageUrl,
    this.selectedModifiers = const [],
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) => OrderItemModel(
        id: json['id'] as String,
        menuItemId: json['menu_item_id'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: double.parse(json['unit_price'].toString()),
        itemName: json['item_name'] as String,
        itemImageUrl: json['item_image_url'] as String?,
        selectedModifiers: (json['selected_modifiers'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            const [],
      );
}

class OrderModel {
  final String id;
  final String restaurantId;
  final String status;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final int? estimatedPrepTimeMinutes;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? cancellationReason;
  final String? cancelledBy;
  final DateTime? acceptanceDeadline;
  final List<OrderItemModel> items;

  const OrderModel({
    required this.id,
    required this.restaurantId,
    required this.status,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.estimatedPrepTimeMinutes,
    required this.createdAt,
    this.updatedAt,
    this.cancellationReason,
    this.cancelledBy,
    this.acceptanceDeadline,
    this.items = const [],
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        status: json['status'] as String,
        subtotal: double.parse(json['subtotal']?.toString() ?? '0'),
        deliveryFee: double.parse(json['delivery_fee']?.toString() ?? '0'),
        total: double.parse(json['total'].toString()),
        estimatedPrepTimeMinutes: json['estimated_prep_time_minutes'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
        cancellationReason: json['cancellation_reason'] as String?,
        cancelledBy: json['cancelled_by'] as String?,
        acceptanceDeadline: json['acceptance_deadline'] != null
            ? DateTime.parse(json['acceptance_deadline'] as String)
            : null,
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => OrderItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
