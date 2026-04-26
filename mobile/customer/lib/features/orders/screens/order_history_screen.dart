import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../../cart/providers/cart_provider.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

final orderHistoryProvider = FutureProvider<List<OrderModel>>(
    (ref) => ref.read(orderServiceProvider).getOrders());

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(orderHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (orders) => orders.isEmpty
            ? const Center(child: Text('No orders yet'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                itemBuilder: (ctx, i) {
                  final o = orders[i];
                  return _OrderCard(order: o);
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
      // Fetch full order with items
      final full =
          await ref.read(orderServiceProvider).getById(widget.order.id);

      if (full.items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No items found for this order')),
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
              content:
                  Text('All items from this order are currently unavailable'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Populate cart — clear any existing cart first
      final cart = ref.read(cartProvider.notifier);
      cart.clear();
      for (final item in availableItems) {
        final menuItem = item.toMenuItemModel(full.restaurantId);
        for (var q = 0; q < item.quantity; q++) {
          cart.addItem(menuItem, full.restaurantId);
        }
      }

      if (mounted) {
        // Warn about unavailable items before navigating
        if (unavailableItems.isNotEmpty) {
          final names = unavailableItems.map((i) => i.itemName).join(', ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Some items are unavailable and were skipped: $names'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
          // Small delay so the snackbar is visible before navigating
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
    final isActive = ![
          'delivered',
          'cancelled',
          'payment_failed',
          'pending_payment',
          'pending_acceptance',
        ].contains(o.status) ||
        o.status == 'pending_acceptance';

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
                        Text(
                          o.restaurantName!,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        'Order #${o.id.substring(0, 8)}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    o.status.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: _statusColor(o.status),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Item summary
            if (o.itemsSummary != null)
              Text(
                o.itemsSummary!,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ETB ${o.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  o.createdAt.toLocal().toString().substring(0, 16),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // Track button for active orders
                if (isActive)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/order/${o.id}/track'),
                      icon: const Icon(Icons.track_changes, size: 16),
                      label: const Text('Track'),
                    ),
                  ),
                // Rate button for delivered orders
                if (o.status == 'delivered') ...[
                  if (isActive) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRatingDialog(context, ref, o.id),
                      icon: const Icon(Icons.star_outline, size: 16),
                      label: const Text('Rate'),
                    ),
                  ),
                ],
                // Reorder button for delivered or cancelled orders
                if (canReorder) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _reordering ? null : _reorder,
                      icon: _reordering
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.replay,
                              size: 16, color: Colors.white),
                      label: Text(
                        _reordering ? 'Adding...' : 'Reorder',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange),
                    ),
                  ),
                ],
              ],
            ),
            // Report a problem — only for delivered orders
            if (o.status == 'delivered') ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _showDisputeDialog(context, ref, o.id),
                  icon: const Icon(Icons.flag_outlined,
                      size: 15, color: Colors.grey),
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
    final reasonCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Report a Problem'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Describe the issue with your order. Our team will review it.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. Wrong items delivered, missing items...',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final reason = reasonCtrl.text.trim();
                      if (reason.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please describe the problem')),
                        );
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        await ref.read(dioClientProvider).dio.post(
                          ApiConstants.disputes,
                          data: {'orderId': orderId, 'reason': reason},
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Dispute submitted. We\'ll review it shortly.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to submit: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showRatingDialog(BuildContext context, WidgetRef ref, String orderId) {
    int restaurantRating = 5;
    int riderRating = 5;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Rate Your Order'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Restaurant'),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    5,
                    (i) => IconButton(
                          icon: Icon(
                              i < restaurantRating
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber),
                          onPressed: () =>
                              setState(() => restaurantRating = i + 1),
                        ))),
            const Text('Rider'),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    5,
                    (i) => IconButton(
                          icon: Icon(
                              i < riderRating ? Icons.star : Icons.star_border,
                              color: Colors.amber),
                          onPressed: () => setState(() => riderRating = i + 1),
                        ))),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await ref.read(orderServiceProvider).rate(orderId,
                    restaurantRating: restaurantRating,
                    riderRating: riderRating);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
