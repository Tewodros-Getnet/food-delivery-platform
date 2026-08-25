import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/restaurant_service.dart';
import '../models/restaurant_model.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/models/cart_item.dart';
import '../providers/favorites_provider.dart';
import '../../auth/providers/auth_provider.dart';

final _detailProvider = FutureProvider.family<RestaurantModel, String>(
    (ref, id) => ref.read(restaurantServiceProvider).getById(id));
final _menuProvider = FutureProvider.family<List<MenuItemModel>, String>(
    (ref, id) => ref.read(restaurantServiceProvider).getMenu(id));
final _ratingsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) =>
        ref.read(restaurantServiceProvider).getRestaurantRatings(id));

class RestaurantDetailScreen extends ConsumerStatefulWidget {
  final String restaurantId;
  const RestaurantDetailScreen({super.key, required this.restaurantId});

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  TabController? _tabController;
  final _categoryKeys = <String, GlobalKey>{};
  List<String> _categories = [];
  bool _suppressTabListener = false;

  // Drives the AppBar background opacity:
  //   0.0 = fully transparent (cover image visible behind the bar)
  //   1.0 = fully opaque surface color (cover collapsed, menu visible)
  double _appBarOpacity = 0.0;

  // The transition runs between these two scroll offsets.
  // expandedHeight is 260; toolbar height ~56; transition starts just before
  // the image is fully hidden and finishes when the bar is pinned on solid.
  static const double _collapseStart = 160.0;
  static const double _collapseEnd   = 220.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  void _buildTabs(List<String> cats) {
    if (_categories.length == cats.length &&
        _categories.every((c) => cats.contains(c))) return;
    _categories = List.from(cats);
    _tabController?.dispose();
    _tabController = TabController(length: cats.length, vsync: this);
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging || _suppressTabListener) return;
      _scrollToCategory(_categories[_tabController!.index]);
    });
    for (final c in cats) {
      _categoryKeys.putIfAbsent(c, () => GlobalKey());
    }
    if (mounted) setState(() {});
  }

  void _scrollToCategory(String cat) {
    final ctx = _categoryKeys[cat]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.05);
  }

  void _onScroll() {
    // ── AppBar opacity ──────────────────────────────────────────────────────
    if (_scrollController.hasClients) {
      final offset = _scrollController.offset;
      final opacity = ((offset - _collapseStart) /
              (_collapseEnd - _collapseStart))
          .clamp(0.0, 1.0);
      if ((opacity - _appBarOpacity).abs() > 0.01) {
        setState(() => _appBarOpacity = opacity);
      }
    }

    // ── Category tab sync ───────────────────────────────────────────────────
    if (_tabController == null || _categories.isEmpty) return;
    int nearest = 0;
    double nearestDist = double.infinity;
    for (int i = 0; i < _categories.length; i++) {
      final ctx = _categoryKeys[_categories[i]]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      final d = (dy - 130).abs();
      if (d < nearestDist) {
        nearestDist = d;
        nearest = i;
      }
    }
    if (_tabController!.index != nearest) {
      _suppressTabListener = true;
      _tabController!.animateTo(nearest);
      Future.delayed(const Duration(milliseconds: 350),
          () => _suppressTabListener = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rAsync = ref.watch(_detailProvider(widget.restaurantId));
    final mAsync = ref.watch(_menuProvider(widget.restaurantId));
    final ratingsAsync = ref.watch(_ratingsProvider(widget.restaurantId));
    final cartCount = ref.watch(cartProvider).totalItems;

    return Scaffold(
      body: rAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (r) {
          return NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (ctx, _) => [
              // ── Collapsing cover image ──────────────────────────────────
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                // Background interpolates from transparent → surface color.
                // Using a Builder so we can read the theme inside the sliver.
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: _appBarOpacity),
                // Foreground: white while the image shows, theme-color once collapsed.
                foregroundColor: _appBarOpacity < 0.5
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                // Keep the status bar icons readable over both states.
                systemOverlayStyle: _appBarOpacity < 0.5
                    ? const SystemUiOverlayStyle(
                        statusBarBrightness: Brightness.dark,
                        statusBarIconBrightness: Brightness.light,
                      )
                    : null,
                // Drop-shadow only appears when fully collapsed.
                elevation: _appBarOpacity >= 1.0 ? 2 : 0,
                shadowColor: Colors.black.withValues(alpha: 0.15),
                title: AnimatedOpacity(
                  opacity: _appBarOpacity,
                  duration: const Duration(milliseconds: 80),
                  child: Text(r.name),
                ),
                actions: [
                  Consumer(builder: (ctx, ref, _) {
                    final isFav = ref.watch(favoritesProvider
                        .select((s) => s.contains(widget.restaurantId)));
                    // Icon color tracks the AppBar foreground transition:
                    // white over the cover image, theme onSurface once collapsed.
                    final iconColor = _appBarOpacity < 0.5
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface;
                    return IconButton(
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.red : iconColor,
                      ),
                      onPressed: () => ref
                          .read(favoritesProvider.notifier)
                          .toggle(widget.restaurantId),
                    );
                  }),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  // The cover + overlapping card together inside FlexibleSpaceBar
                  background: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Full cover image
                      Positioned.fill(
                        child: r.coverImageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: r.coverImageUrl!,
                                fit: BoxFit.cover)
                            : Container(color: Colors.orange),
                      ),

                      // Info card — centred on the bottom edge of the cover
                      // top = coverHeight - cardHeight/2
                      // card height ≈ 110px so offset = 260 - 55 = 205
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 170,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Logo + Name + open badge
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (r.logoUrl != null) ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: r.logoUrl!,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) =>
                                              Container(
                                            width: 44,
                                            height: 44,
                                            color: Colors.white12,
                                            child: const Icon(
                                                Icons.storefront,
                                                color: Colors.white38,
                                                size: 22),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Text(
                                        r.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: r.isOpen
                                            ? Colors.green.shade600
                                            : Colors.red.shade600,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        r.isOpen ? 'Open' : 'Closed',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Rating + address
                                Row(children: [
                                  const Icon(Icons.star_rounded,
                                      color: Colors.amber, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    r.averageRating.toStringAsFixed(1),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      r.address,
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ]),
                                // Description
                                if (r.description != null &&
                                    r.description!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    r.description!,
                                    style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                        height: 1.4),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Space to account for half the card overlapping below ────
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // ── Scrollable info section ─────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (r.promoBannerText != null ||
                          r.promoBannerImageUrl != null) ...[
                        _PromoBanner(
                            text: r.promoBannerText,
                            imageUrl: r.promoBannerImageUrl),
                        const SizedBox(height: 10),
                      ],
                      if (!r.isOpen) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Text(
                            'This restaurant is currently closed.',
                            style: TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (r.operatingHours != null) ...[
                        _OperatingHoursWidget(
                            operatingHours: r.operatingHours!),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Sticky category tab bar ─────────────────────────────────
              if (_tabController != null)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorColor: Colors.orange,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelColor: Colors.orange,
                      unselectedLabelColor: Colors.grey,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      tabs: _categories.map((c) => Tab(text: c)).toList(),
                    ),
                  ),
                ),
            ],
            body: mAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                      child: Text('No menu items yet.',
                          style: TextStyle(color: Colors.grey)));
                }

                // Group by category
                final grouped = <String, List<MenuItemModel>>{};
                for (final item in items) {
                  grouped
                      .putIfAbsent(item.category ?? 'Other', () => [])
                      .add(item);
                }
                final cats = grouped.keys.toList();

                // Build tabs after frame
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _buildTabs(cats));

                // Flat list: header + items per category
                final rows = <Widget>[];
                for (final cat in cats) {
                  rows.add(Padding(
                    key: _categoryKeys.putIfAbsent(cat, () => GlobalKey()),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Row(children: [
                      Text(cat,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Divider(
                              color: Colors.grey[300], thickness: 1)),
                    ]),
                  ));
                  for (final item in grouped[cat]!) {
                    rows.add(_MenuTile(
                        item: item,
                        restaurantId: widget.restaurantId,
                        isRestaurantOpen: r.isOpen));
                  }
                }

                // Reviews
                rows.add(const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text('Reviews',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ));
                ratingsAsync.whenData((ratings) {
                  if (ratings.isEmpty) {
                    rows.add(const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text('No reviews yet.',
                          style: TextStyle(color: Colors.grey)),
                    ));
                  } else {
                    rows.addAll(
                        ratings.map((r) => _ReviewTile(rating: r)));
                  }
                });

                rows.add(const SizedBox(height: 80));

                return ListView(children: rows);
              },
            ),
          );
        },
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

// ── Sticky tab bar delegate ───────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) => tabBar != old.tabBar;
}


// ── Menu item tile ────────────────────────────────────────────────────────────

class _MenuTile extends ConsumerWidget {
  final MenuItemModel item;
  final String restaurantId;
  final bool isRestaurantOpen;
  const _MenuTile(
      {required this.item,
      required this.restaurantId,
      required this.isRestaurantOpen});

  void _handleAdd(BuildContext context, WidgetRef ref) {
    final authStatus = ref.read(authProvider).status;
    if (authStatus == AuthStatus.guest ||
        authStatus == AuthStatus.unauthenticated) {
      // Go to landing page directly — no bottom sheet needed
      context.go('/landing');
      return;
    }

    if (item.modifiers.isNotEmpty) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _ModifierSheet(item: item, restaurantId: restaurantId),
      );
    } else {
      final added = ref.read(cartProvider.notifier).addItem(item, restaurantId);
      if (!added) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Clear Cart?'),
            content: const Text('Your cart has items from another restaurant. Clear it?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                  onPressed: () {
                    ref.read(cartProvider.notifier).clearAndAdd(item, restaurantId);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Clear & Add', style: TextStyle(color: Colors.orange))),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAvailable = item.available;
    final canAdd = isRestaurantOpen && isAvailable;
    final cartItems = ref.watch(cartProvider).items;
    final qtyInCart = cartItems
        .where((ci) => ci.menuItem.id == item.id)
        .fold(0, (sum, ci) => sum + ci.quantity);

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  if (item.description != null && item.description!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(item.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    Text('ETB ${item.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    if (!isAvailable) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('Sold Out',
                            style: TextStyle(color: Colors.white, fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                    if (item.modifiers.isNotEmpty && isAvailable) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.orange.shade200)),
                        child: const Text('Customisable',
                            style: TextStyle(color: Colors.orange, fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: item.imageUrl,
                    width: 88, height: 88, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                        width: 88, height: 88, color: Colors.grey[200],
                        child: const Icon(Icons.fastfood, color: Colors.grey, size: 32)),
                  ),
                ),
                const SizedBox(height: 6),
                if (!canAdd)
                  const SizedBox(height: 32)
                else if (qtyInCart == 0)
                  GestureDetector(
                    onTap: () => _handleAdd(context, ref),
                    child: Container(
                      width: 88, height: 32,
                      decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('Add',
                              style: TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    width: 88, height: 32,
                    decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: () {
                            final match = cartItems.firstWhere(
                                (ci) => ci.menuItem.id == item.id,
                                orElse: () => cartItems.first);
                            ref.read(cartProvider.notifier)
                                .updateQuantity(match.cartKey, match.quantity - 1);
                          },
                          child: const Icon(Icons.remove, color: Colors.white, size: 16),
                        ),
                        Text('$qtyInCart',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        GestureDetector(
                          onTap: () => _handleAdd(context, ref),
                          child: const Icon(Icons.add, color: Colors.white, size: 16),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Promo banner ──────────────────────────────────────────────────────────────

class _PromoBanner extends StatelessWidget {
  final String? text;
  final String? imageUrl;
  const _PromoBanner({this.text, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          CachedNetworkImage(
              imageUrl: imageUrl!, height: 120, width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _textBanner()),
          if (text != null && text!.isNotEmpty)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent])),
                child: Text(text!,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
        ]),
      );
    }
    return _textBanner();
  }

  Widget _textBanner() {
    if (text == null || text!.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange.shade600, Colors.orange.shade400]),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.local_offer, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text!,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
      ]),
    );
  }
}

// ── Modifier sheet ────────────────────────────────────────────────────────────

class _ModifierSheet extends ConsumerStatefulWidget {
  final MenuItemModel item;
  final String restaurantId;
  const _ModifierSheet({required this.item, required this.restaurantId});

  @override
  ConsumerState<_ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends ConsumerState<_ModifierSheet> {
  final Map<String, Set<String>> _selections = {};

  @override
  void initState() {
    super.initState();
    for (final group in widget.item.modifiers) {
      if (group.required && group.type == 'single' && group.options.isNotEmpty) {
        _selections[group.name] = {group.options.first.name};
      }
    }
  }

  bool get _canAdd {
    for (final group in widget.item.modifiers) {
      if (group.required) {
        final sel = _selections[group.name];
        if (sel == null || sel.isEmpty) return false;
      }
    }
    return true;
  }

  double get _extraPrice {
    double extra = 0;
    for (final group in widget.item.modifiers) {
      for (final optName in _selections[group.name] ?? {}) {
        extra += group.options
            .firstWhere((o) => o.name == optName,
                orElse: () => const ModifierOption(name: '', price: 0))
            .price;
      }
    }
    return extra;
  }

  void _addToCart() {
    final mods = <SelectedModifier>[];
    for (final group in widget.item.modifiers) {
      for (final optName in _selections[group.name] ?? {}) {
        final opt = group.options.firstWhere((o) => o.name == optName,
            orElse: () => const ModifierOption(name: '', price: 0));
        mods.add(SelectedModifier(group: group.name, option: optName, price: opt.price));
      }
    }
    final added = ref.read(cartProvider.notifier)
        .addItem(widget.item, widget.restaurantId, selectedModifiers: mods);
    Navigator.pop(context);
    if (!added) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Clear Cart?'),
          content: const Text('Your cart has items from another restaurant. Clear it?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
                onPressed: () {
                  ref.read(cartProvider.notifier).clearAndAdd(
                      widget.item, widget.restaurantId, selectedModifiers: mods);
                  Navigator.pop(ctx);
                },
                child: const Text('Clear & Add')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Base price: ETB ${widget.item.price.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            ...widget.item.modifiers.map((group) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(group.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  if (group.required) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('Required',
                          style: TextStyle(color: Colors.red, fontSize: 10)),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                ...group.options.map((opt) {
                  final isSelected = _selections[group.name]?.contains(opt.name) ?? false;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: group.type == 'single'
                        ? Radio<String>(
                            value: opt.name,
                            groupValue: _selections[group.name]?.firstOrNull,
                            onChanged: (v) {
                              if (v != null) setState(() => _selections[group.name] = {v});
                            })
                        : Checkbox(
                            value: isSelected,
                            onChanged: (v) {
                              setState(() {
                                _selections.putIfAbsent(group.name, () => {});
                                if (v == true) {
                                  _selections[group.name]!.add(opt.name);
                                } else {
                                  _selections[group.name]!.remove(opt.name);
                                }
                              });
                            }),
                    title: Text(opt.name),
                    trailing: opt.price > 0
                        ? Text('+ETB ${opt.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: Colors.orange, fontWeight: FontWeight.w600))
                        : null,
                  );
                }),
                const SizedBox(height: 8),
              ],
            )),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canAdd ? _addToCart : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(
                  'Add to Cart — ETB ${(widget.item.price + _extraPrice).toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Operating hours widget ────────────────────────────────────────────────────

class _OperatingHoursWidget extends StatefulWidget {
  final Map<String, dynamic> operatingHours;
  const _OperatingHoursWidget({required this.operatingHours});

  @override
  State<_OperatingHoursWidget> createState() => _OperatingHoursWidgetState();
}

class _OperatingHoursWidgetState extends State<_OperatingHoursWidget> {
  bool _expanded = false;
  static const _days = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
  static const _labels = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  static const _fullLabels = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];

  String _today() {
    const d = ['sunday','monday','tuesday','wednesday','thursday','friday','saturday'];
    return d[DateTime.now().weekday % 7];
  }

  String _hours(String day) {
    final e = widget.operatingHours[day] as Map<String, dynamic>?;
    if (e == null) return '—';
    if (e['closed'] == true) return 'Closed';
    return '${e['open']} – ${e['close']}';
  }

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final todayText = _hours(today);
    final todayLabel = _fullLabels[_days.indexOf(today)];
    final isClosed = todayText == 'Closed' || todayText == '—';

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              const Icon(Icons.access_time, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text('Today ($todayLabel): ',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(todayText,
                  style: TextStyle(
                      fontSize: 13,
                      color: isClosed ? Colors.red : Colors.green.shade700,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: Colors.grey),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              children: List.generate(_days.length, (i) {
                final h = _hours(_days[i]);
                final closed = h == 'Closed' || h == '—';
                final isToday = _days[i] == today;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(
                      width: 36,
                      child: Text(_labels[i],
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                              color: isToday ? Colors.orange : Colors.black87)),
                    ),
                    Text(h,
                        style: TextStyle(
                            fontSize: 12,
                            color: closed ? Colors.red.shade400 : Colors.green.shade700,
                            fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                  ]),
                );
              }),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── Review tile ───────────────────────────────────────────────────────────────

class _ReviewTile extends StatelessWidget {
  final Map<String, dynamic> rating;
  const _ReviewTile({required this.rating});

  @override
  Widget build(BuildContext context) {
    final score = (rating['rating'] as num?)?.toInt() ?? 0;
    final review = rating['review'] as String?;
    final name = rating['customer_name'] as String? ?? 'Customer';
    final createdAt = rating['created_at'] != null
        ? DateTime.tryParse(rating['created_at'] as String)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.orange.shade100,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              if (createdAt != null)
                Text('${createdAt.day}/${createdAt.month}/${createdAt.year}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ]),
          ),
          Row(
            children: List.generate(5, (i) => Icon(
              i < score ? Icons.star : Icons.star_border,
              color: Colors.amber, size: 14)),
          ),
        ]),
        if (review != null && review.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Text(review, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          ),
        ],
        if ((rating['reply'] as String?) != null &&
            (rating['reply'] as String).isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.storefront, size: 13, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text('Restaurant reply',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                          color: Colors.green.shade700)),
                ]),
                const SizedBox(height: 4),
                Text(rating['reply'] as String,
                    style: TextStyle(fontSize: 12, color: Colors.green.shade900)),
              ]),
            ),
          ),
        ],
        const Divider(height: 20),
      ]),
    );
  }
}
