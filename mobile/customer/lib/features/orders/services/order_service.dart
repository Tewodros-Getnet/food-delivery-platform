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
          .map((i) => {
                'menuItemId': i.menuItem.id,
                'quantity': i.quantity,
                if (i.selectedModifiers.isNotEmpty)
                  'selectedModifiers':
                      i.selectedModifiers.map((m) => m.toJson()).toList(),
              })
          .toList(),
    });
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<OrderModel>> getOrders() async {
    final res = await _client.dio.get(ApiConstants.orders);
    final raw = res.data['data'];
    // Handle both old (List) and new paginated (Map with orders key) response shapes
    final list = raw is List
        ? raw
        : (raw as Map<String, dynamic>)['orders'] as List<dynamic>;
    return list
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Paginated version used by the order history screen.
  /// Returns orders + pagination metadata.
  Future<Map<String, dynamic>> getOrdersPaginated({
    int page = 1,
    int limit = 15,
  }) async {
    final res = await _client.dio.get(
      ApiConstants.orders,
      queryParameters: {'page': page, 'limit': limit},
    );
    final data = res.data['data'] as Map<String, dynamic>;
    // Backend returns { orders: [...], pagination: {...} }
    final orders = (data['orders'] as List<dynamic>)
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return {
      'orders': orders,
      'pagination': data['pagination'] as Map<String, dynamic>,
    };
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
