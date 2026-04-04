import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/restaurant_model.dart';
import '../services/restaurant_service.dart';

final restaurantListProvider =
    FutureProvider.family<List<RestaurantModel>, String?>(
  (ref, category) =>
      ref.read(restaurantServiceProvider).getRestaurants(category: category),
);

final restaurantDetailProvider = FutureProvider.family<RestaurantModel, String>(
  (ref, id) => ref.read(restaurantServiceProvider).getById(id),
);

final menuItemsProvider = FutureProvider.family<List<MenuItemModel>, String>(
  (ref, restaurantId) =>
      ref.read(restaurantServiceProvider).getMenu(restaurantId),
);

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<Map<String, dynamic>>((ref) {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return Future.value({'restaurants': [], 'menuItems': []});
  return ref.read(restaurantServiceProvider).search(query);
});
