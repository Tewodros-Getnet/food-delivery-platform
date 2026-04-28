import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../restaurants/services/restaurant_service.dart';
import '../../restaurants/models/restaurant_model.dart';
import '../../cart/providers/cart_provider.dart';

final restaurantsProvider = FutureProvider<List<RestaurantModel>>(
    (ref) => ref.read(restaurantServiceProvider).getRestaurants());

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Search state
  String? _query;
  bool _searching = false;
  List<RestaurantModel> _searchRestaurants = [];
  List<MenuItemModel> _searchMenuItems = [];
  String? _searchError;

  // Category filter state — null means "All"
  String? _selectedCategory;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _query = null;
        _searchRestaurants = [];
        _searchMenuItems = [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce =
        Timer(const Duration(milliseconds: 400), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _query = q;
      _searchError = null;
    });
    try {
      final result = await ref.read(restaurantServiceProvider).search(q);
      if (!mounted) return;
      final rawRestaurants = result['restaurants'] as List<dynamic>? ?? [];
      final rawMenuItems = result['menuItems'] as List<dynamic>? ?? [];
      setState(() {
        _searchRestaurants = rawRestaurants
            .map((e) => RestaurantModel.fromJson(e as Map<String, dynamic>))
            .toList();
        _searchMenuItems = rawMenuItems
            .map((e) => MenuItemModel.fromJson(e as Map<String, dynamic>))
            .toList();
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = 'Search failed. Please try again.';
        _searching = false;
      });
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _onSearchChanged('');
  }

  /// Extract unique non-null categories from the loaded restaurant list.
  List<String> _categories(List<RestaurantModel> list) {
    final seen = <String>{};
    final result = <String>[];
    for (final r in list) {
      if (r.category != null && seen.add(r.category!)) {
        result.add(r.category!);
      }
    }
    result.sort();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final restaurants = ref.watch(restaurantsProvider);
    final cartCount = ref.watch(cartProvider).totalItems;
    final isSearchActive = _query != null && _query!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Delivery'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: cartCount > 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/cart'),
              backgroundColor: Colors.orange,
              icon: const Icon(Icons.shopping_cart, color: Colors.white),
              label: Text('Cart ($cartCount)',
                  style: const TextStyle(color: Colors.white)),
            )
          : null,
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search restaurants or food...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: isSearchActive
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),

          // Category chips — only shown when not searching and restaurants loaded
          if (!isSearchActive)
            restaurants.maybeWhen(
              data: (list) {
                final cats = _categories(list);
                if (cats.isEmpty) return const SizedBox.shrink();
                return SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      // "All" chip
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text('All'),
                          selected: _selectedCategory == null,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = null),
                          selectedColor: Colors.orange,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: _selectedCategory == null
                                ? Colors.white
                                : Colors.black87,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      // Category chips
                      ...cats.map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(cat),
                              selected: _selectedCategory == cat,
                              onSelected: (_) => setState(() =>
                                  _selectedCategory =
                                      _selectedCategory == cat ? null : cat),
                              selectedColor: Colors.orange,
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _selectedCategory == cat
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 12,
                              ),
                            ),
                          )),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),

          // Body: search results or filtered restaurant list
          Expanded(
            child: isSearchActive
                ? _SearchResults(
                    query: _query!,
                    searching: _searching,
                    restaurants: _searchRestaurants,
                    menuItems: _searchMenuItems,
                    error: _searchError,
                  )
                : restaurants.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (list) {
                      // Apply category filter
                      final filtered = _selectedCategory == null
                          ? list
                          : list
                              .where((r) => r.category == _selectedCategory)
                              .toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.restaurant,
                                  size: 56, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                'No restaurants in "$_selectedCategory"',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 15),
                              ),
                            ],
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: () =>
                            ref.refresh(restaurantsProvider.future),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) =>
                              _RestaurantCard(restaurant: filtered[i]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Search results widget ─────────────────────────────────────────────────────

class _SearchResults extends StatelessWidget {
  final String query;
  final bool searching;
  final List<RestaurantModel> restaurants;
  final List<MenuItemModel> menuItems;
  final String? error;

  const _SearchResults({
    required this.query,
    required this.searching,
    required this.restaurants,
    required this.menuItems,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: Colors.grey, size: 48),
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: Colors.grey)),
        ]),
      );
    }
    if (restaurants.isEmpty && menuItems.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.search_off, color: Colors.grey, size: 56),
          const SizedBox(height: 12),
          Text('No results for "$query"',
              style: const TextStyle(color: Colors.grey, fontSize: 15)),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        if (restaurants.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Restaurants',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          ...restaurants.map((r) => _RestaurantCard(restaurant: r)),
        ],
        if (menuItems.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Menu Items',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          ...menuItems.map((item) => _MenuItemSearchCard(item: item)),
        ],
      ],
    );
  }
}

// ── Menu item search result card ──────────────────────────────────────────────

class _MenuItemSearchCard extends StatelessWidget {
  final MenuItemModel item;
  const _MenuItemSearchCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: item.imageUrl,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              width: 56,
              height: 56,
              color: Colors.grey[200],
              child: const Icon(Icons.fastfood, color: Colors.grey),
            ),
          ),
        ),
        title: Text(item.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('ETB ${item.price.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.orange)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/restaurant/${item.restaurantId}'),
      ),
    );
  }
}

// ── Restaurant card ───────────────────────────────────────────────────────────

class _RestaurantCard extends StatelessWidget {
  final RestaurantModel r;
  const _RestaurantCard({required RestaurantModel restaurant}) : r = restaurant;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => context.push('/restaurant/${r.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Cover image with open/closed overlay
          Stack(children: [
            r.coverImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: r.coverImageUrl!,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(height: 150, color: Colors.grey[200]),
                    errorWidget: (_, __, ___) => Container(
                        height: 150,
                        color: Colors.grey[200],
                        child: const Icon(Icons.restaurant,
                            size: 48, color: Colors.grey)))
                : Container(
                    height: 150,
                    color: Colors.grey[200],
                    child: const Center(
                        child: Icon(Icons.restaurant,
                            size: 48, color: Colors.grey))),
            // Closed overlay
            if (!r.isOpen)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('CLOSED',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1)),
                  ),
                ),
              ),
            // Category pill (top-left)
            if (r.category != null)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(r.category!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
          // Info row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(children: [
                // Rating
                const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                const SizedBox(width: 3),
                Text(r.averageRating.toStringAsFixed(1),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                // Minimum order
                if (r.minimumOrderValue != null &&
                    r.minimumOrderValue! > 0) ...[
                  const Icon(Icons.shopping_bag_outlined,
                      size: 13, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text('Min ETB ${r.minimumOrderValue!.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 12),
                ],
                // Open status dot
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: r.isOpen ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(r.isOpen ? 'Open' : 'Closed',
                    style: TextStyle(
                        fontSize: 12,
                        color: r.isOpen ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
