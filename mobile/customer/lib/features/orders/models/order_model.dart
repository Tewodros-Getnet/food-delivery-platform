import '../../restaurants/models/restaurant_model.dart';

class OrderItemModel {
  final String id;
  final String menuItemId;
  final int quantity;
  final double unitPrice;
  final String itemName;
  final String? itemImageUrl;
  final bool available; // current availability from menu_items table

  const OrderItemModel({
    required this.id,
    required this.menuItemId,
    required this.quantity,
    required this.unitPrice,
    required this.itemName,
    this.itemImageUrl,
    required this.available,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) => OrderItemModel(
        id: json['id'] as String,
        menuItemId: json['menu_item_id'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: double.parse(json['unit_price'].toString()),
        itemName: json['item_name'] as String,
        itemImageUrl: json['item_image_url'] as String?,
        available: json['available'] as bool? ?? false,
      );

  // Convert to MenuItemModel for cart (requires restaurantId from parent order)
  MenuItemModel toMenuItemModel(String restaurantId) => MenuItemModel(
        id: menuItemId,
        restaurantId: restaurantId,
        name: itemName,
        price: unitPrice,
        imageUrl: itemImageUrl ?? '',
        available: available,
      );
}

class OrderModel {
  final String id;
  final String customerId;
  final String restaurantId;
  final String? riderId;
  final String status;
  final String? paymentStatus;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final DateTime createdAt;
  final DateTime? estimatedDeliveryTime;
  final int? estimatedPrepTimeMinutes;
  // Coordinates for live tracking map
  final double? restaurantLat;
  final double? restaurantLon;
  final double? deliveryLat;
  final double? deliveryLon;
  final List<OrderItemModel> items;
  final String? restaurantName; // from list endpoint JOIN
  final String? itemsSummary; // e.g. "Burger x2, Fries x1"

  const OrderModel({
    required this.id,
    required this.customerId,
    required this.restaurantId,
    this.riderId,
    required this.status,
    this.paymentStatus,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.createdAt,
    this.estimatedDeliveryTime,
    this.estimatedPrepTimeMinutes,
    this.restaurantLat,
    this.restaurantLon,
    this.deliveryLat,
    this.deliveryLon,
    this.items = const [],
    this.restaurantName,
    this.itemsSummary,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        id: json['id'] as String,
        customerId: json['customer_id'] as String,
        restaurantId: json['restaurant_id'] as String,
        riderId: json['rider_id'] as String?,
        status: json['status'] as String,
        paymentStatus: json['payment_status'] as String?,
        subtotal: double.parse(json['subtotal'].toString()),
        deliveryFee: double.parse(json['delivery_fee'].toString()),
        total: double.parse(json['total'].toString()),
        createdAt: DateTime.parse(json['created_at'] as String),
        estimatedDeliveryTime: json['estimated_delivery_time'] != null
            ? DateTime.parse(json['estimated_delivery_time'] as String)
            : null,
        estimatedPrepTimeMinutes: json['estimated_prep_time_minutes'] as int?,
        restaurantLat: (json['restaurant_lat'] as num?)?.toDouble(),
        restaurantLon: (json['restaurant_lon'] as num?)?.toDouble(),
        deliveryLat: (json['delivery_lat'] as num?)?.toDouble(),
        deliveryLon: (json['delivery_lon'] as num?)?.toDouble(),
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => OrderItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        restaurantName: json['restaurant_name'] as String?,
        itemsSummary: json['items_summary'] as String?,
      );

  String get statusMessage =>
      const {
        'confirmed': 'Your order has been confirmed and is being prepared.',
        'ready_for_pickup':
            'Your food is ready. A rider is on the way to pick it up.',
        'rider_assigned':
            'A rider has been assigned and is heading to the restaurant.',
        'picked_up': 'Your rider has picked up your food and is on the way.',
        'delivered': 'Your order has been delivered. Enjoy your meal.',
        'cancelled': 'Your order has been cancelled.',
        'payment_failed': 'Payment failed. Please try again.',
        'pending_payment': 'Waiting for payment confirmation...',
      }[status] ??
      'Processing your order...';

  bool get isPaymentFailed => status == 'payment_failed';
  bool get isPendingPayment => status == 'pending_payment';
}
