import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';

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
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text('Order #${o.id.substring(0, 8)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.status.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                    color: _statusColor(o.status),
                                    fontSize: 12)),
                            Text('ETB ${o.total.toStringAsFixed(2)}'),
                            Text(o.createdAt
                                .toLocal()
                                .toString()
                                .substring(0, 16)),
                          ]),
                      trailing: o.status == 'delivered'
                          ? TextButton(
                              onPressed: () =>
                                  _showRatingDialog(context, ref, o.id),
                              child: const Text('Rate'))
                          : IconButton(
                              icon: const Icon(Icons.track_changes),
                              onPressed: () =>
                                  context.push('/order/${o.id}/track')),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Color _statusColor(String s) =>
      const {
        'delivered': Colors.green,
        'cancelled': Colors.red,
        'confirmed': Colors.blue,
        'picked_up': Colors.orange,
      }[s] ??
      Colors.grey;

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
