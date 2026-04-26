import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import '../models/order_model.dart';

final orderServiceProvider = Provider<OrderService>(
  (ref) => OrderService(ref.read(dioClientProvider)),
);

class OrderService {
  final DioClient _client;
  OrderService(this._client);

  Future<List<OrderModel>> getOrders() async {
    final res = await _client.dio.get(ApiConstants.orders);
    final list = res.data['data'] as List<dynamic>;
    return list
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markReady(String orderId, {int? prepTime}) async {
    await _client.dio.put(
      '${ApiConstants.orders}/$orderId/status',
      data: {
        'status': 'ready_for_pickup',
        if (prepTime != null) 'estimatedPrepTime': prepTime,
      },
    );
  }

  Future<void> cancelOrder(String orderId, String reason) async {
    await _client.dio.put(
      '${ApiConstants.orders}/$orderId/restaurant-cancel',
      data: {'reason': reason},
    );
  }

  Future<void> acceptOrder(String orderId,
      {int? estimatedPrepTimeMinutes}) async {
    await _client.dio.put(
      '${ApiConstants.orders}/$orderId/accept',
      data: {
        if (estimatedPrepTimeMinutes != null)
          'estimatedPrepTimeMinutes': estimatedPrepTimeMinutes,
      },
    );
  }

  Future<void> rejectOrder(String orderId, String reason) async {
    await _client.dio.put(
      '${ApiConstants.orders}/$orderId/reject',
      data: {'reason': reason},
    );
  }
}
