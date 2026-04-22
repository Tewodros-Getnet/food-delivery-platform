import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import '../models/restaurant_model.dart';

final restaurantServiceProvider = Provider<RestaurantService>(
    (ref) => RestaurantService(ref.read(dioClientProvider)));

class RestaurantService {
  final DioClient _client;
  RestaurantService(this._client);

  Future<List<RestaurantModel>> getRestaurants({String? category}) async {
    final res = await _client.dio.get(ApiConstants.restaurants,
        queryParameters: {if (category != null) 'category': category});
    final list = res.data['data']['restaurants'] as List<dynamic>;
    return list
        .map((e) => RestaurantModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RestaurantModel> getById(String id) async {
    final res = await _client.dio.get('${ApiConstants.restaurants}/$id');
    return RestaurantModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<List<MenuItemModel>> getMenu(String restaurantId) async {
    final res =
        await _client.dio.get('${ApiConstants.restaurants}/$restaurantId/menu');
    final list = res.data['data'] as List<dynamic>;
    return list
        .map((e) => MenuItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> search(String q) async {
    final res =
        await _client.dio.get(ApiConstants.search, queryParameters: {'q': q});
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getRestaurantRatings(
      String restaurantId) async {
    final res = await _client.dio
        .get('${ApiConstants.restaurants}/$restaurantId/ratings');
    final list = res.data['data'] as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }
}
