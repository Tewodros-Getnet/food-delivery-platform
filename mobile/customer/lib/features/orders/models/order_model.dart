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
