import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../core/constants/api_constants.dart';
import '../../../core/storage/secure_storage.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../../auth/providers/auth_provider.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  List<OrderModel> _orders = [];
  bool _loading = true;
  io.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _load();
    _connect();
  }

  Future<void> _load() async {
    try {
      final orders = await ref.read(orderServiceProvider).getOrders();
      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    final token = await ref.read(secureStorageProvider).getJwt();
    if (token == null) return;
    _socket = io.io(
      ApiConstants.wsUrl,
      io.OptionBuilder().setTransports(['websocket']).setAuth({
        'token': token,
      }).build(),
    );
    _socket!.on('order:status_changed', (_) => _load());
  }

  @override
  void dispose() {
    _socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _orders
        .where(
          (o) => [
            'confirmed',
            'ready_for_pickup',
            'rider_assigned',
            'picked_up',
          ].contains(o.status),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.restaurant_menu),
            onPressed: () {
              final restaurantId =
                  _orders.isNotEmpty ? _orders.first.restaurantId : null;
              if (restaurantId != null) {
                context.push('/menu/$restaurantId');
              } else {
                context.push('/setup');
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : active.isEmpty
              ? const Center(child: Text('No active orders'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: active.length,
                    itemBuilder: (ctx, i) => _OrderCard(
                      order: active[i],
                      onMarkReady: () async {
                        await ref
                            .read(orderServiceProvider)
                            .markReady(active[i].id);
                        await _load();
                      },
                    ),
                  ),
                ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onMarkReady;
  const _OrderCard({required this.order, required this.onMarkReady});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order #${order.id.substring(0, 8)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Chip(
                  label: Text(
                    order.status.replaceAll('_', ' '),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  backgroundColor: _statusColor(order.status),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Total: ETB ${order.total.toStringAsFixed(2)}'),
            Text(
              'Time: ${order.createdAt.toLocal().toString().substring(11, 16)}',
            ),
            if (order.status == 'confirmed') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onMarkReady,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                  ),
                  child: const Text(
                    'Mark Ready for Pickup',
                    style: TextStyle(color: Colors.white),
                  ),
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
        'confirmed': Colors.blue,
        'ready_for_pickup': Colors.orange,
        'rider_assigned': Colors.purple,
        'picked_up': Colors.teal,
      }[s] ??
      Colors.grey;
}
