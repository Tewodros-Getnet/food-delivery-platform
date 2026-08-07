import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../../cart/providers/cart_provider.dart';
import '../../restaurants/services/restaurant_service.dart';
import '../../../core/widgets/retry_widget.dart';
import '../../../l10n/app_localizations.dart';

final orderHistoryProvider = FutureProvider<List<OrderModel>>(
    (ref) => ref.read(orderServiceProvider).getOrders());

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});
  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(orderHistoryProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ordersAsync = ref.watch(orderHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myOrders),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.retry,
            onPressed: () => ref.invalidate(orderHistoryProvider),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetryWidget(
          error: e,
          onRetry: () => ref.invalidate(orderHistoryProvider),
        ),
        data: (orders) => orders.isEmpty
            ? Center(child: Text(l10n.noOrders))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(orderHistoryProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  itemBuilder: (ctx, i) => _OrderCard(order: orders[i]),
                ),
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
    final l10n = AppLocalizations.of(context);
    setState(() => _reordering = true);
    try {
      final full = await ref.read(orderServiceProvider).getById(widget.order.id);

      if (full.items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.noItemsFound)),
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
              content: Text('${restaurant.name} ${l10n.closed.toLowerCase()}'),
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
            SnackBar(
              content: Text(l10n.allItemsUnavailable),
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
              content: Text(l10n.someItemsUnavailable(names)),
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
            content: Text(l10n.failedToReorder(e.toString())),
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
    final l10n = AppLocalizations.of(context);
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
                      Text('${l10n.orderNumber}${o.id.substring(0, 8)}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    o.status.replaceAll('_', ' ').toUpperCase(),
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
                      label: Text(l10n.track),
                    ),
                  ),
                if (o.status == 'delivered') ...[
                  if (isActive) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRatingDialog(context, ref, o.id),
                      icon: const Icon(Icons.star_outline, size: 16),
                      label: Text(l10n.rate),
                    ),
                  ),
                ],
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
                        _reordering ? l10n.adding : l10n.reorder,
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
                  label: Text(l10n.reportProblem,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(String s) =>
      const {
        'pending_acceptance': Colors.orange,
        'delivered': Colors.green,
        'cancelled': Colors.red,
        'confirmed': Colors.blue,
        'picked_up': Colors.orange,
        'ready_for_pickup': Colors.amber,
        'rider_assigned': Colors.purple,
        'pending_payment': Colors.grey,
        'payment_failed': Colors.red,
      }[s] ??
      Colors.grey;

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
