import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/restaurant_model.dart';
import '../services/restaurant_service.dart';

final restaurantListProvider =
    FutureProvider.family<List<RestaurantModel>, String?>(
  (ref, category) =>
      ref.read(restaurantServiceProvider).getRestaurants(category: category),
);

final restaurantsProvider = FutureProvider<List<RestaurantModel>>(
  (ref) => ref.read(restaurantServiceProvider).getRestaurants(),
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

class NearbyParams {
  final double lat;
  final double lon;
  final double radius;
  const NearbyParams({required this.lat, required this.lon, this.radius = 10});

  @override
  bool operator ==(Object other) =>
      other is NearbyParams && lat == other.lat && lon == other.lon && radius == other.radius;

  @override
  int get hashCode => Object.hash(lat, lon, radius);
}

final nearbyRestaurantsProvider =
    FutureProvider.family<List<RestaurantModel>, NearbyParams>(
  (ref, params) => ref
      .read(restaurantServiceProvider)
      .getNearbyRestaurants(lat: params.lat, lon: params.lon, radius: params.radius),
);
