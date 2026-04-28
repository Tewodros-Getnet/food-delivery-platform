import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import '../models/restaurant_model.dart';

// Set of favorited restaurant IDs — fast O(1) lookup for heart icon state
final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Set<String>>(
    (ref) => FavoritesNotifier(ref.read(dioClientProvider)));

class FavoritesNotifier extends StateNotifier<Set<String>> {
  final DioClient _client;
  FavoritesNotifier(this._client) : super({}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.dio.get(ApiConstants.favorites);
      final list = res.data['data'] as List<dynamic>;
      state =
          list.map((e) => (e as Map<String, dynamic>)['id'] as String).toSet();
    } catch (_) {}
  }

  bool isFavorite(String restaurantId) => state.contains(restaurantId);

  Future<void> toggle(String restaurantId) async {
    final wasFavorite = state.contains(restaurantId);
    // Optimistic update
    final updated = Set<String>.from(state);
    if (wasFavorite) {
      updated.remove(restaurantId);
    } else {
      updated.add(restaurantId);
    }
    state = updated;
    try {
      if (wasFavorite) {
        await _client.dio.delete('${ApiConstants.favorites}/$restaurantId');
      } else {
        await _client.dio.post('${ApiConstants.favorites}/$restaurantId');
      }
    } catch (_) {
      // Revert on error
      final reverted = Set<String>.from(state);
      if (wasFavorite) {
        reverted.add(restaurantId);
      } else {
        reverted.remove(restaurantId);
      }
      state = reverted;
    }
  }
}

// Full restaurant objects for the favorites list screen
final favoriteRestaurantsProvider =
    FutureProvider<List<RestaurantModel>>((ref) async {
  final client = ref.read(dioClientProvider);
  final res = await client.dio.get(ApiConstants.favorites);
  final list = res.data['data'] as List<dynamic>;
  return list
      .map((e) => RestaurantModel.fromJson(e as Map<String, dynamic>))
      .toList();
});
