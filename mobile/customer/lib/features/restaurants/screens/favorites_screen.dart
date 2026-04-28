import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/favorites_provider.dart';
import '../models/restaurant_model.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favAsync = ref.watch(favoriteRestaurantsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Restaurants'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: favAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (restaurants) => restaurants.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.favorite_border,
                        size: 72, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    const Text('No saved restaurants yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    const Text('Tap the ♥ on any restaurant to save it',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: restaurants.length,
                itemBuilder: (ctx, i) => _FavCard(r: restaurants[i]),
              ),
      ),
    );
  }
}

class _FavCard extends ConsumerWidget {
  final RestaurantModel r;
  const _FavCard({required this.r});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => context.push('/restaurant/${r.id}'),
        child: Row(children: [
          // Image
          r.coverImageUrl != null
              ? CachedNetworkImage(
                  imageUrl: r.coverImageUrl!,
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                      width: 90,
                      height: 90,
                      color: Colors.grey[200],
                      child: const Icon(Icons.restaurant,
                          color: Colors.grey, size: 32)),
                )
              : Container(
                  width: 90,
                  height: 90,
                  color: Colors.grey[200],
                  child: const Icon(Icons.restaurant,
                      color: Colors.grey, size: 32)),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                if (r.category != null)
                  Text(r.category!,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                  const SizedBox(width: 3),
                  Text(r.averageRating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 10),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: r.isOpen ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(r.isOpen ? 'Open' : 'Closed',
                      style: TextStyle(
                          fontSize: 11,
                          color: r.isOpen ? Colors.green : Colors.red)),
                ]),
              ],
            ),
          ),
          // Remove heart
          IconButton(
            icon: const Icon(Icons.favorite, color: Colors.red, size: 20),
            onPressed: () => ref.read(favoritesProvider.notifier).toggle(r.id),
          ),
        ]),
      ),
    );
  }
}
