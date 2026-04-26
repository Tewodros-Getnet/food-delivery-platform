class OrderModel {
  final String id;
  final String restaurantId;
  final String status;
  final double total;
  final int? estimatedPrepTimeMinutes;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? cancellationReason;
  final String? cancelledBy;
  final DateTime? acceptanceDeadline;

  const OrderModel({
    required this.id,
    required this.restaurantId,
    required this.status,
    required this.total,
    this.estimatedPrepTimeMinutes,
    required this.createdAt,
    this.updatedAt,
    this.cancellationReason,
    this.cancelledBy,
    this.acceptanceDeadline,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        status: json['status'] as String,
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
      );
}
