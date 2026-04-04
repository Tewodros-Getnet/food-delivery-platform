import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/restaurant_service.dart';
import '../models/restaurant_model.dart';
import '../../cart/providers/cart_provider.dart';

final _detailProvider = FutureProvider.family<RestaurantModel, String>(
    (ref, id) => ref.read(restaurantServiceProvider).getById(id));
final _menuProvider = FutureProvider.family<List<MenuItemModel>, String>(
    (ref, id) => ref.read(restaurantServiceProvider).getMenu(id));

class RestaurantDetailScreen extends ConsumerWidget {
  final String restaurantId;
  const RestaurantDetailScreen({super.key, required this.restaurantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rAsync = ref.watch(_detailProvider(restaurantId));
    final mAsync = ref.watch(_menuProvider(restaurantId));
    final cartCount = ref.watch(cartProvider).totalItems;

    return Scaffold(
      body: rAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (r) => CustomScrollView(slivers: [
          SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(r.name,
                    style: const TextStyle(shadows: [Shadow(blurRadius: 4)])),
                background: r.coverImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: r.coverImageUrl!, fit: BoxFit.cover)
                    : Container(color: Colors.orange),
              )),
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          const SizedBox(width: 4),
                          Text(r.averageRating.toStringAsFixed(1)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(r.address,
                                  style: TextStyle(color: Colors.grey[600]))),
                        ]),
                        if (r.description != null) ...[
                          const SizedBox(height: 8),
                          Text(r.description!)
                        ],
                        const Divider(height: 24),
                        const Text('Menu',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ]))),
          mAsync.when(
            loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverToBoxAdapter(child: Text('Error: $e')),
            data: (items) => SliverList(
                delegate: SliverChildBuilderDelegate(
                    (ctx, i) =>
                        _MenuTile(item: items[i], restaurantId: restaurantId),
                    childCount: items.length)),
          ),
        ]),
      ),
      floatingActionButton: cartCount > 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/cart'),
              label: Text('Cart ($cartCount)'),
              icon: const Icon(Icons.shopping_cart),
              backgroundColor: Colors.orange)
          : null,
    );
  }
}

class _MenuTile extends ConsumerWidget {
  final MenuItemModel item;
  final String restaurantId;
  const _MenuTile({required this.item, required this.restaurantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
              imageUrl: item.imageUrl,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                  width: 64,
                  height: 64,
                  color: Colors.grey[200],
                  child: const Icon(Icons.fastfood, color: Colors.grey)))),
      title:
          Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (item.description != null)
          Text(item.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        Text('ETB ${item.price.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Colors.orange, fontWeight: FontWeight.bold)),
      ]),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle, color: Colors.orange, size: 32),
        onPressed: () {
          final added =
              ref.read(cartProvider.notifier).addItem(item, restaurantId);
          if (!added) {
            showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                      title: const Text('Clear Cart?'),
                      content: const Text(
                          'Your cart has items from another restaurant. Clear it?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () {
                              ref
                                  .read(cartProvider.notifier)
                                  .clearAndAdd(item, restaurantId);
                              Navigator.pop(ctx);
                            },
                            child: const Text('Clear & Add')),
                      ],
                    ));
          }
        },
      ),
    );
  }
}
