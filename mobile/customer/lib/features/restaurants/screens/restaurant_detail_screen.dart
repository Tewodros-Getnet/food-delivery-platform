import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/restaurant_service.dart';
import '../models/restaurant_model.dart';
import '../../cart/providers/cart_provider.dart';
import '../../cart/models/cart_item.dart';

final _detailProvider = FutureProvider.family<RestaurantModel, String>(
    (ref, id) => ref.read(restaurantServiceProvider).getById(id));
final _menuProvider = FutureProvider.family<List<MenuItemModel>, String>(
    (ref, id) => ref.read(restaurantServiceProvider).getMenu(id));
final _ratingsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) =>
        ref.read(restaurantServiceProvider).getRestaurantRatings(id));

class RestaurantDetailScreen extends ConsumerWidget {
  final String restaurantId;
  const RestaurantDetailScreen({super.key, required this.restaurantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rAsync = ref.watch(_detailProvider(restaurantId));
    final mAsync = ref.watch(_menuProvider(restaurantId));
    final ratingsAsync = ref.watch(_ratingsProvider(restaurantId));
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
                        // Promotional banner
                        if (r.promoBannerText != null ||
                            r.promoBannerImageUrl != null) ...[
                          _PromoBanner(
                            text: r.promoBannerText,
                            imageUrl: r.promoBannerImageUrl,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(children: [
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          const SizedBox(width: 4),
                          Text(r.averageRating.toStringAsFixed(1)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(r.address,
                                  style: TextStyle(color: Colors.grey[600]))),
                          if (!r.isOpen)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('CLOSED',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                        ]),
                        if (!r.isOpen) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: const Text(
                              'This restaurant is currently closed and not accepting orders.',
                              style: TextStyle(color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                        if (r.description != null) ...[
                          const SizedBox(height: 8),
                          Text(r.description!)
                        ],
                        // Operating hours section
                        if (r.operatingHours != null) ...[
                          const SizedBox(height: 12),
                          _OperatingHoursWidget(
                              operatingHours: r.operatingHours!),
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
            data: (items) {
              if (items.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No menu items yet.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                );
              }

              // Group items by category
              final grouped = <String, List<MenuItemModel>>{};
              for (final item in items) {
                final cat = item.category ?? 'Other';
                grouped.putIfAbsent(cat, () => []).add(item);
              }

              // Build a flat list of category headers + item tiles
              final sliverItems = <Widget>[];
              grouped.forEach((category, categoryItems) {
                // Category header
                sliverItems.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                );
                // Items in this category
                for (final item in categoryItems) {
                  sliverItems.add(_MenuTile(
                    item: item,
                    restaurantId: restaurantId,
                    isRestaurantOpen: r.isOpen,
                  ));
                }
              });

              return SliverList(
                delegate: SliverChildListDelegate(sliverItems),
              );
            },
          ),

          // ── Reviews section ──────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Reviews',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
          ratingsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox()),
            data: (ratings) => ratings.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Text('No reviews yet.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _ReviewTile(rating: ratings[i]),
                      childCount: ratings.length,
                    ),
                  ),
          ),
          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
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
  final bool isRestaurantOpen;
  const _MenuTile(
      {required this.item,
      required this.restaurantId,
      required this.isRestaurantOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAvailable = item.available;
    final canAdd = isRestaurantOpen && isAvailable;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.5,
      child: ListTile(
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
        title: Text(item.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (item.description != null)
            Text(item.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          Row(
            children: [
              Text('ETB ${item.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.bold)),
              if (!isAvailable) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Sold Out',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ]),
        trailing: IconButton(
          icon: Icon(Icons.add_circle,
              color: canAdd ? Colors.orange : Colors.grey, size: 32),
          onPressed: canAdd
              ? () {
                  if (item.modifiers.isNotEmpty) {
                    // Show modifier selection sheet
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _ModifierSheet(
                        item: item,
                        restaurantId: restaurantId,
                      ),
                    );
                  } else {
                    // No modifiers — add directly
                    final added = ref
                        .read(cartProvider.notifier)
                        .addItem(item, restaurantId);
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
                  }
                }
              : null,
        ),
      ),
    );
  }
}

// ── Promo banner widget ───────────────────────────────────────────────────────

class _PromoBanner extends StatelessWidget {
  final String? text;
  final String? imageUrl;

  const _PromoBanner({this.text, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl!,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _textOnlyBanner(),
            ),
            if (text != null && text!.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Text(
                    text!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return _textOnlyBanner();
  }

  Widget _textOnlyBanner() {
    if (text == null || text!.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade600, Colors.orange.shade400],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_offer, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text!,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Modifier selection bottom sheet ──────────────────────────────────────────

class _ModifierSheet extends ConsumerStatefulWidget {
  final MenuItemModel item;
  final String restaurantId;

  const _ModifierSheet({required this.item, required this.restaurantId});

  @override
  ConsumerState<_ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends ConsumerState<_ModifierSheet> {
  // group name → selected option name(s)
  final Map<String, Set<String>> _selections = {};

  @override
  void initState() {
    super.initState();
    // Pre-select first option for required single groups
    for (final group in widget.item.modifiers) {
      if (group.required &&
          group.type == 'single' &&
          group.options.isNotEmpty) {
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
      final sel = _selections[group.name] ?? {};
      for (final optName in sel) {
        final opt = group.options.firstWhere(
          (o) => o.name == optName,
          orElse: () => const ModifierOption(name: '', price: 0),
        );
        extra += opt.price;
      }
    }
    return extra;
  }

  void _addToCart() {
    final selectedModifiers = <SelectedModifier>[];
    for (final group in widget.item.modifiers) {
      final sel = _selections[group.name] ?? {};
      for (final optName in sel) {
        final opt = group.options.firstWhere(
          (o) => o.name == optName,
          orElse: () => const ModifierOption(name: '', price: 0),
        );
        selectedModifiers.add(SelectedModifier(
          group: group.name,
          option: optName,
          price: opt.price,
        ));
      }
    }

    final added = ref.read(cartProvider.notifier).addItem(
          widget.item,
          widget.restaurantId,
          selectedModifiers: selectedModifiers,
        );

    Navigator.pop(context);

    if (!added) {
      // Different restaurant — show clear cart dialog
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
                  ref.read(cartProvider.notifier).clearAndAdd(
                        widget.item,
                        widget.restaurantId,
                        selectedModifiers: selectedModifiers,
                      );
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
    final totalPrice = widget.item.price + _extraPrice;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Base price: ETB ${widget.item.price.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ...widget.item.modifiers.map((group) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        group.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (group.required) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Required',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...group.options.map((opt) {
                    final isSelected =
                        _selections[group.name]?.contains(opt.name) ?? false;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: group.type == 'single'
                          ? Radio<String>(
                              value: opt.name,
                              groupValue: _selections[group.name]?.firstOrNull,
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selections[group.name] = {v});
                                }
                              },
                            )
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
                              },
                            ),
                      title: Text(opt.name),
                      trailing: opt.price > 0
                          ? Text(
                              '+ETB ${opt.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600),
                            )
                          : null,
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canAdd ? _addToCart : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Add to Cart — ETB ${totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
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

  static const _days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  static const _dayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const _fullDayLabels = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  String _todayName() {
    const days = [
      'sunday',
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday'
    ];
    return days[DateTime.now().weekday % 7];
  }

  String _hoursText(String day) {
    final entry = widget.operatingHours[day] as Map<String, dynamic>?;
    if (entry == null) return '—';
    if (entry['closed'] == true) return 'Closed';
    final open = entry['open'] as String? ?? '';
    final close = entry['close'] as String? ?? '';
    return '$open – $close';
  }

  @override
  Widget build(BuildContext context) {
    final today = _todayName();
    final todayText = _hoursText(today);
    final todayLabel = _fullDayLabels[_days.indexOf(today)];
    final isTodayClosed = todayText == 'Closed' || todayText == '—';

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Today's hours row (always visible)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Today ($todayLabel): ',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    todayText,
                    style: TextStyle(
                      fontSize: 13,
                      color: isTodayClosed ? Colors.red : Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          // Full weekly schedule (collapsible)
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                children: List.generate(_days.length, (i) {
                  final day = _days[i];
                  final label = _dayLabels[i];
                  final hours = _hoursText(day);
                  final isClosed = hours == 'Closed' || hours == '—';
                  final isToday = day == today;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isToday ? FontWeight.bold : FontWeight.normal,
                              color: isToday ? Colors.orange : Colors.black87,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            hours,
                            style: TextStyle(
                              fontSize: 12,
                              color: isClosed
                                  ? Colors.red.shade400
                                  : Colors.green.shade700,
                              fontWeight:
                                  isToday ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.orange.shade100,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    if (createdAt != null)
                      Text(
                        '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                  ],
                ),
              ),
              // Star rating
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < score ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          if (review != null && review.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Text(
                review,
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ),
          ],
          // Restaurant reply
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storefront,
                            size: 13, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Restaurant reply',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rating['reply'] as String,
                      style:
                          TextStyle(fontSize: 12, color: Colors.green.shade900),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Divider(height: 20),
        ],
      ),
    );
  }
}
