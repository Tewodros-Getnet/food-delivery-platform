import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../restaurants/services/restaurant_service.dart';
import '../../restaurants/models/restaurant_model.dart';
import '../../cart/providers/cart_provider.dart';
import '../../restaurants/providers/favorites_provider.dart';
import '../../../core/widgets/retry_widget.dart';
import '../../../l10n/app_localizations.dart';

final restaurantsProvider = FutureProvider<List<RestaurantModel>>(
    (ref) => ref.read(restaurantServiceProvider).getRestaurants());

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-fetch restaurant list when app resumes so stale/error state recovers
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(restaurantsProvider);
    }
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

    // Determine the filtered list once so slivers can reference it.
    final allRestaurants = restaurants.asData?.value ?? [];
    final filtered = _selectedCategory == null
        ? allRestaurants
        : allRestaurants.where((r) => r.category == _selectedCategory).toList();
    final cats = _categories(allRestaurants);

    return Scaffold(
      floatingActionButton: cartCount > 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/cart'),
              backgroundColor: Colors.orange,
              icon: const Icon(Icons.shopping_cart, color: Colors.white),
              label: Text('${AppLocalizations.of(context).cart} ($cartCount)',
                  style: const TextStyle(color: Colors.white)),
            )
          : null,
      body: isSearchActive
          // ── Search mode: plain scaffold with results list ──────────────
          ? Column(
              children: [
                _buildSearchBar(context, isSearchActive),
                Expanded(
                  child: _SearchResults(
                    query: _query!,
                    searching: _searching,
                    restaurants: _searchRestaurants,
                    menuItems: _searchMenuItems,
                    error: _searchError,
                  ),
                ),
              ],
            )
          // ── Browse mode: CustomScrollView with SliverAppBar ────────────
          : RefreshIndicator(
              onRefresh: () => ref.refresh(restaurantsProvider.future),
              child: CustomScrollView(
                slivers: [
                  // Floating app bar — collapses as user scrolls down
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    title: Text(AppLocalizations.of(context).appTitle),
                    // No backgroundColor / foregroundColor — inherits AppBarTheme
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(56),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: _buildSearchBar(context, isSearchActive),
                      ),
                    ),
                  ),

                  // Category chips
                  if (cats.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(AppLocalizations.of(context).all),
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
                            ...cats.map((cat) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(cat),
                                    selected: _selectedCategory == cat,
                                    onSelected: (_) => setState(() =>
                                        _selectedCategory =
                                            _selectedCategory == cat
                                                ? null
                                                : cat),
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
                      ),
                    ),

                  // Restaurant list / loading / error states
                  restaurants.when(
                    loading: () => const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => SliverFillRemaining(
                      child: RetryWidget(
                        error: e,
                        onRetry: () => ref.refresh(restaurantsProvider),
                      ),
                    ),
                    data: (_) {
                      if (filtered.isEmpty) {
                        return SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.restaurant,
                                    size: 56, color: Colors.grey),
                                const SizedBox(height: 12),
                                Text(
                                  '${AppLocalizations.of(context).noResultsFor} "$_selectedCategory"',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        sliver: SliverList.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) =>
                              _RestaurantCard(restaurant: filtered[i]),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  /// Reusable search bar widget used in both browse and search layouts.
  Widget _buildSearchBar(BuildContext context, bool isSearchActive) {
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).searchRestaurants,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: isSearchActive
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSearch,
              )
            : null,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        isDense: true,
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
          Text(AppLocalizations.of(context).searchFailed,
              style: const TextStyle(color: Colors.grey)),
        ]),
      );
    }
    if (restaurants.isEmpty && menuItems.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.search_off, color: Colors.grey, size: 56),
          const SizedBox(height: 12),
          Text('${AppLocalizations.of(context).noResultsFor} "$query"',
              style: const TextStyle(color: Colors.grey, fontSize: 15)),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        if (restaurants.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(AppLocalizations.of(context).searchRestaurants,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          ...restaurants.map((r) => _RestaurantCard(restaurant: r)),
        ],
        if (menuItems.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(AppLocalizations.of(context).menuItems,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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

// ── Restaurant cover placeholder ─────────────────────────────────────────────
// Shown when a restaurant has no cover image (or while one is loading).
// Uses a warm gradient derived from the restaurant's name initial so every
// card looks intentional rather than broken.

class _RestaurantPlaceholder extends StatelessWidget {
  final String name;
  final double height;
  const _RestaurantPlaceholder({required this.name, this.height = 180});

  /// Pick one of several warm gradient pairs based on the first letter so
  /// different restaurants get visually distinct colours.
  List<Color> _gradientColors() {
    const palettes = [
      [Color(0xFFFF8C00), Color(0xFFFF5722)], // orange → deep-orange
      [Color(0xFFE91E63), Color(0xFF9C27B0)], // pink → purple
      [Color(0xFF2196F3), Color(0xFF00BCD4)], // blue → cyan
      [Color(0xFF4CAF50), Color(0xFF8BC34A)], // green → light-green
      [Color(0xFF795548), Color(0xFFFF8C00)], // brown → orange
      [Color(0xFF607D8B), Color(0xFF455A64)], // blue-grey shades
      [Color(0xFFFF5722), Color(0xFFF44336)], // deep-orange → red
      [Color(0xFF9C27B0), Color(0xFF3F51B5)], // purple → indigo
    ];
    final idx = name.isNotEmpty
        ? name.toUpperCase().codeUnitAt(0) % palettes.length
        : 0;
    return palettes[idx];
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final colors = _gradientColors();

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Large faded initial in the background
          Positioned(
            right: -12,
            bottom: -16,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 120,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.12),
                height: 1,
              ),
            ),
          ),
          // Centred initial + label
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantCard extends ConsumerWidget {
  final RestaurantModel r;
  const _RestaurantCard({required RestaurantModel restaurant}) : r = restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(favoritesProvider.select((s) => s.contains(r.id)));

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => context.push('/restaurant/${r.id}'),
        child: SizedBox(
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Cover image ───────────────────────────────────────────
              r.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: r.coverImageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          _RestaurantPlaceholder(name: r.name, height: 180),
                      errorWidget: (_, __, ___) =>
                          _RestaurantPlaceholder(name: r.name, height: 180))
                  : _RestaurantPlaceholder(name: r.name, height: 180),

              // ── Bottom gradient overlay ───────────────────────────────
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.35, 0.7, 1.0],
                    ),
                  ),
                ),
              ),

              // ── Closed overlay ────────────────────────────────────────
              if (!r.isOpen)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
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

              // ── Category pill (top-left) ──────────────────────────────
              if (r.category != null)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
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

              // ── Favorite button (top-right) ───────────────────────────
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () =>
                      ref.read(favoritesProvider.notifier).toggle(r.id),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4)
                      ],
                    ),
                    child: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.red : Colors.grey[600],
                      size: 18,
                    ),
                  ),
                ),
              ),

              // ── Logo + Info bar at bottom ─────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Logo
                      if (r.logoUrl != null) ...[
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6)
                            ],
                          ),
                          child: ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: r.logoUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey[800],
                                child: const Icon(Icons.storefront,
                                    size: 24, color: Colors.white70),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      // Name + rating
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black54)
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.star_rounded,
                                  size: 15, color: Colors.amber),
                              const SizedBox(width: 3),
                              Text(r.averageRating.toStringAsFixed(1),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              if (r.category != null) ...[
                                const SizedBox(width: 6),
                                Text('·',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.6))),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(r.category!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
                                          fontSize: 13)),
                                ),
                              ],
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: r.isOpen
                                      ? Colors.green.withValues(alpha: 0.85)
                                      : Colors.red.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  r.isOpen ? 'Open' : 'Closed',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
