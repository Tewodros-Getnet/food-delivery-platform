class OrderModel {
  final String id;
  final String restaurantId;
  final String status;
  final double total;
  final int? estimatedPrepTimeMinutes;
  final DateTime createdAt;
  final String? cancellationReason;
  final String? cancelledBy;

  const OrderModel({
    required this.id,
    required this.restaurantId,
    required this.status,
    required this.total,
    this.estimatedPrepTimeMinutes,
    required this.createdAt,
    this.cancellationReason,
    this.cancelledBy,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        status: json['status'] as String,
        total: double.parse(json['total'].toString()),
        estimatedPrepTimeMinutes: json['estimated_prep_time_minutes'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
        cancellationReason: json['cancellation_reason'] as String?,
        cancelledBy: json['cancelled_by'] as String?,
      );
}
