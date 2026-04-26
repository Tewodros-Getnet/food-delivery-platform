import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

final menuServiceProvider = Provider<MenuService>(
  (ref) => MenuService(ref.read(dioClientProvider)),
);

class MenuService {
  final DioClient _client;
  MenuService(this._client);

  Future<List<dynamic>> getItems(String restaurantId) async {
    final res = await _client.dio.get(
      '${ApiConstants.restaurants}/$restaurantId/menu',
    );
    return res.data['data'] as List<dynamic>;
  }

  Future<void> createItem(
    String restaurantId,
    Map<String, dynamic> data,
  ) async {
    await _client.dio.post(
      '${ApiConstants.restaurants}/$restaurantId/menu',
      data: data,
    );
  }

  Future<void> updateItem(String id, Map<String, dynamic> data) async {
    await _client.dio.put('${ApiConstants.menu}/$id', data: data);
  }

  Future<void> deleteItem(String id) async {
    await _client.dio.delete('${ApiConstants.menu}/$id');
  }

  /// Toggles the `available` field of a menu item.
  /// Uses PATCH for semantic correctness; returns the updated item map.
  Future<Map<String, dynamic>> toggleAvailability(String id) async {
    final res =
        await _client.dio.patch('${ApiConstants.menu}/$id/availability');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getItemById(String id) async {
    final res = await _client.dio.get('${ApiConstants.menu}/$id');
    return res.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateModifiers(
      String id, List<Map<String, dynamic>> modifiers) async {
    final res = await _client.dio.put(
      '${ApiConstants.menu}/$id/modifiers',
      data: modifiers,
    );
    return res.data['data'] as Map<String, dynamic>;
  }
}
