import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import '../models/order_model.dart';
import '../../cart/models/cart_item.dart';

final orderServiceProvider =
    Provider<OrderService>((ref) => OrderService(ref.read(dioClientProvider)));

class OrderService {
  final DioClient _client;
  OrderService(this._client);

  Future<Map<String, dynamic>> createOrder({
    required String restaurantId,
    required String deliveryAddressId,
    required List<CartItem> items,
  }) async {
    final res = await _client.dio.post(ApiConstants.orders, data: {
      'restaurantId': restaurantId,
      'deliveryAddressId': deliveryAddressId,
      'items': items
          .map((i) => {'menuItemId': i.menuItem.id, 'quantity': i.quantity})
          .toList(),
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<OrderModel>> getOrders() async {
    final res = await _client.dio.get(ApiConstants.orders);
    final list = res.data['data'] as List<dynamic>;
    return list
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<OrderModel> getById(String id) async {
    final res = await _client.dio.get('${ApiConstants.orders}/$id');
    return OrderModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> cancel(String id, {String? reason}) async {
    await _client.dio.put('${ApiConstants.orders}/$id/cancel',
        data: {if (reason != null) 'reason': reason});
  }

  Future<void> rate(String id,
      {int? restaurantRating, int? riderRating, String? review}) async {
    await _client.dio.post('${ApiConstants.orders}/$id/rate', data: {
      if (restaurantRating != null) 'restaurantRating': restaurantRating,
      if (riderRating != null) 'riderRating': riderRating,
      if (review != null) 'review': review,
    });
  }
}
