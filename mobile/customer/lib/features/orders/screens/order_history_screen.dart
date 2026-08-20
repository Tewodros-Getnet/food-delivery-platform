import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../../cart/providers/cart_provider.dart';
import '../../restaurants/services/restaurant_service.dart';
import '../../../core/widgets/retry_widget.dart';

final orderHistoryProvider = FutureProvider<List<OrderModel>>(
    (ref) => ref.read(orderServiceProvider).getOrders());

// ── Friendly status labels (customer-facing) ──────────────────────────────────

String _friendlyStatus(String status) => const {
      'pending_payment':    'Awaiting payment',
      'pending_acceptance': 'Waiting for restaurant',
      'confirmed':          'Being prepared',
      'ready_for_pickup':   'Waiting for rider',
      'rider_assigned':     'On the way',
      'picked_up':          'On the way',
      'delivered':          'Delivered',
      'cancelled':          'Cancelled',
      'payment_failed':     'Payment failed',
    }[status] ??
    status.replaceAll('_', ' ');

Color _statusColor(String s) => const {
      'pending_acceptance': Colors.orange,
      'confirmed':          Colors.blue,
      'ready_for_pickup':   Colors.amber,
      'rider_assigned':     Colors.purple,
      'picked_up':          Colors.purple,
      'delivered':          Colors.green,
      'cancelled':          Colors.red,
      'payment_failed':     Colors.red,
      'pending_payment':    Colors.grey,
    }[s] ??
    Colors.grey;

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});
  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final List<OrderModel> _orders = [];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load(reset: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      if (mounted) setState(() { _loading = true; _error = null; _page = 1; _hasMore = true; });
    } else {
      if (!_hasMore || _loadingMore) return;
      if (mounted) setState(() => _loadingMore = true);
    }

    try {
      final result = await ref
          .read(orderServiceProvider)
          .getOrdersPaginated(page: reset ? 1 : _page, limit: 15);
      final newOrders = result['orders'] as List<OrderModel>;
      final pagination = result['pagination'] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          if (reset) _orders
            ..clear()
            ..addAll(newOrders);
          else
            _orders.addAll(newOrders);
          _page = (pagination['page'] as int) + 1;
          _hasMore = pagination['hasMore'] as bool? ?? false;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _loadingMore = false; _error = e; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep orderHistoryProvider in sync so ref.invalidate works from RatingScreen
    ref.listen<AsyncValue<List<OrderModel>>>(orderHistoryProvider, (_, next) {
      next.whenData((_) => _load(reset: true));
    });

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Orders')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _orders.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Orders')),
        body: RetryWidget(error: _error!, onRetry: () => _load(reset: true)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(orderHistoryProvider);
              _load(reset: true);
            },
          ),
        ],
      ),
      body: _orders.isEmpty
          ? const Center(child: Text('No orders yet'))
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length + (_loadingMore ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == _orders.length) {
                    // Loading more indicator at the bottom
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _OrderCard(order: _orders[i]);
                },
              ),
            ),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  final OrderModel order;
  const _OrderCard({required this.order});

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _reordering = false;

  Future<void> _reorder() async {
    setState(() => _reordering = true);
    try {
      final full = await ref.read(orderServiceProvider).getById(widget.order.id);

      if (full.items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No items found')),
          );
        }
        return;
      }

      final restaurant =
          await ref.read(restaurantServiceProvider).getById(full.restaurantId);
      if (!restaurant.isOpen) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${restaurant.name} is closed'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final availableItems = full.items.where((i) => i.available).toList();
      final unavailableItems = full.items.where((i) => !i.available).toList();

      if (availableItems.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All items are currently unavailable'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final cart = ref.read(cartProvider.notifier);
      cart.clear();
      for (final item in availableItems) {
        final menuItem = item.toMenuItemModel(full.restaurantId);
        final modifiers = item.toSelectedModifiers();
        for (var q = 0; q < item.quantity; q++) {
          cart.addItem(menuItem, full.restaurantId, selectedModifiers: modifiers);
        }
      }

      if (mounted) {
        if (unavailableItems.isNotEmpty) {
          final names = unavailableItems.map((i) => i.itemName).join(', ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Some items unavailable and were skipped: $names'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 600));
        }
        if (mounted) context.push('/cart');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reorder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final canReorder = o.status == 'delivered' || o.status == 'cancelled';
    final isActive = [
      'pending_acceptance', 'confirmed', 'ready_for_pickup',
      'rider_assigned', 'picked_up',
    ].contains(o.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (o.restaurantName != null)
                        Text(o.restaurantName!,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis),
                      Text('Order #${o.id.substring(0, 8)}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    _friendlyStatus(o.status),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: _statusColor(o.status),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (o.itemsSummary != null)
              Text(o.itemsSummary!,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ETB ${o.total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(o.createdAt.toLocal().toString().substring(0, 16),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (isActive)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/order/${o.id}/track'),
                      icon: const Icon(Icons.track_changes, size: 16),
                      label: const Text('Track'),
                    ),
                  ),
                if (o.status == 'delivered' && !o.hasRated) ...[
                  if (isActive) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRatingDialog(context, ref, o.id),
                      icon: const Icon(Icons.star_outline, size: 16),
                      label: const Text('Rate'),
                    ),
                  ),
                ],
                if (o.status == 'delivered' && o.hasRated)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.star_rounded,
                          size: 16, color: Colors.amber),
                      label: const Text('Rated'),
                    ),
                  ),
                if (canReorder) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _reordering ? null : _reorder,
                      icon: _reordering
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.replay, size: 16, color: Colors.white),
                      label: Text(
                        _reordering ? 'Adding...' : 'Reorder',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    ),
                  ),
                ],
              ],
            ),
            if (o.status == 'delivered') ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _showDisputeDialog(context, ref, o.id),
                  icon: const Icon(Icons.flag_outlined, size: 15, color: Colors.grey),
                  label: const Text('Report a problem',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDisputeDialog(BuildContext context, WidgetRef ref, String orderId) {
    context.push('/order/$orderId/dispute', extra: {
      'restaurantName': widget.order.restaurantName,
      'itemsSummary': widget.order.itemsSummary,
    });
  }

  void _showRatingDialog(BuildContext context, WidgetRef ref, String orderId) {
    context.push('/order/$orderId/rate',
        extra: {'restaurantName': widget.order.restaurantName, 'riderName': null});
  }

}
