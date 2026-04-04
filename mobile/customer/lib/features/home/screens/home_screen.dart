import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../restaurants/services/restaurant_service.dart';
import '../../restaurants/models/restaurant_model.dart';
import '../../cart/providers/cart_provider.dart';

final restaurantsProvider = FutureProvider<List<RestaurantModel>>(
    (ref) => ref.read(restaurantServiceProvider).getRestaurants());

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurants = ref.watch(restaurantsProvider);
    final cartCount = ref.watch(cartProvider).totalItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Delivery'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (cartCount > 0)
            Stack(children: [
              IconButton(
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: () => context.push('/cart')),
              Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                      radius: 8,
                      backgroundColor: Colors.red,
                      child: Text('$cartCount',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white)))),
            ]),
          IconButton(
              icon: const Icon(Icons.receipt_long),
              onPressed: () => context.push('/orders')),
          IconButton(
              icon: const Icon(Icons.person),
              onPressed: () => context.push('/profile')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search restaurants or food...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: (v) {/* search handled by provider */},
            ),
          ),
          Expanded(
            child: restaurants.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => RefreshIndicator(
                onRefresh: () => ref.refresh(restaurantsProvider.future),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) => _RestaurantCard(restaurant: list[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  final RestaurantModel r;
  const _RestaurantCard({required RestaurantModel restaurant}) : r = restaurant;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/restaurant/${r.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (r.coverImageUrl != null)
            CachedNetworkImage(
                imageUrl: r.coverImageUrl!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(height: 140, color: Colors.grey[200]),
                errorWidget: (_, __, ___) => Container(
                    height: 140,
                    color: Colors.grey[200],
                    child: const Icon(Icons.restaurant,
                        size: 48, color: Colors.grey))),
          Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              if (r.category != null)
                Text(r.category!,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.star, size: 15, color: Colors.amber),
                const SizedBox(width: 3),
                Text(r.averageRating.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 13)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
