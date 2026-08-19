import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../widgets/pending_acceptance_order_card.dart';
import '../widgets/elapsed_timer.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/fcm_service.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with WidgetsBindingObserver {
  List<OrderModel> _pendingOrders = []; // pending_acceptance
  List<OrderModel> _activeOrders = []; // confirmed, ready_for_pickup, etc.
  bool _loading = true;
  bool _loadError = false; // true when restaurant/orders fetch failed
  String? _restaurantId;
  bool _isOpen = true;
  io.Socket? _socket;
  int _retryCount = 0;
  static const int _maxAutoRetries = 4;       // retry up to 4× on resume
  static const int _retryDelaySeconds = 8;    // 8s between retries (server wake-up)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWithRetry();
    _connect();
    onOrdersReloadRequested = () {
      if (mounted) _load();
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Reset retry counter and try loading — will auto-retry if server
      // is cold-starting (Render free tier spins down after inactivity).
      _retryCount = 0;
      _loadWithRetry();
    }
  }

  Future<void> _loadWithRetry() async {
    setState(() { _loading = true; _loadError = false; });
    while (_retryCount <= _maxAutoRetries) {
      try {
        await _load();
        return; // success — stop retrying
      } catch (_) {
        _retryCount++;
        if (_retryCount > _maxAutoRetries) {
          if (mounted) setState(() { _loading = false; _loadError = true; });
          return;
        }
        // Wait before next retry so server has time to wake up
        await Future.delayed(Duration(seconds: _retryDelaySeconds));
        if (!mounted) return;
      }
    }
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioClientProvider).dio;

      // Fetch restaurant info
      try {
        final rRes = await dio.get(ApiConstants.myRestaurant);
        final rData = rRes.data['data'] as Map<String, dynamic>?;
        _restaurantId = rData?['id'] as String?;
        if (mounted) setState(() => _isOpen = (rData?['is_open'] as bool?) ?? true);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          _restaurantId = null;
        } else {
          // Rethrow so _loadWithRetry can catch it
          rethrow;
        }
      }

      final orders = await ref.read(orderServiceProvider).getOrders();
      if (!mounted) return;
      setState(() {
        if (_restaurantId == null && orders.isNotEmpty) {
          _restaurantId = orders.first.restaurantId;
        }
        _pendingOrders =
            orders.where((o) => o.status == 'pending_acceptance').toList();
        _activeOrders = orders
            .where((o) => [
                  'confirmed',
                  'ready_for_pickup',
                  'rider_assigned',
                  'picked_up'
                ].contains(o.status))
            .toList();
        _loading = false;
        _loadError = false;
        _retryCount = 0;
      });
    } catch (_) {
      // Rethrow — caller (_loadWithRetry or manual retry) handles state
      rethrow;
    }
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Could not load restaurant data',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _retryCount = 0;
                _loadWithRetry();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(160, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.storefront_outlined,
                  size: 64, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 24),
            const Text(
              'Set Up Your Restaurant',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'You haven\'t registered your restaurant yet. Complete your setup to start receiving orders.',
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => context.push('/setup'),
              icon: const Icon(Icons.add_business),
              label: const Text('Register Restaurant',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect() async {
    _socket?.disconnect();
    final token = await ref.read(secureStorageProvider).getJwt();
    if (token == null) return;
    _socket = io.io(
      ApiConstants.wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    // New order requiring acceptance
    _socket!.on('order:acceptance_request', (data) {
      if (!mounted) return;
      // Alert sound + vibration so the owner doesn't miss it
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      Future.delayed(
          const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
      Future.delayed(
          const Duration(milliseconds: 600), HapticFeedback.heavyImpact);
      try {
        final orderData = (data['data']['order'] as Map<String, dynamic>?) ??
            (data['data'] as Map<String, dynamic>);
        final order = OrderModel.fromJson(orderData);
        setState(() {
          // Add if not already present
          if (!_pendingOrders.any((o) => o.id == order.id)) {
            _pendingOrders.insert(0, order);
          }
        });
      } catch (_) {
        // Fallback: reload all orders
        _load();
      }
    });

    // Any status change — reload to keep lists in sync
    _socket!.on('order:status_changed', (_) {
      if (mounted) _load();
    });

    _socket!.on('order:searching_rider', (data) {
      final d = data['data'] as Map<String, dynamic>?;
      if (mounted && d != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Looking for a rider for order ${(d['orderId'] as String).substring(0, 8)}... '
              '(attempt ${d['retryCount']}/${d['maxRetries']})',
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });

    _socket!.on('connect_error', (err) async {
      final errStr = err.toString();
      if (errStr.contains('Invalid token') ||
          errStr.contains('Authentication')) {
        final storage = ref.read(secureStorageProvider);
        final rt = await storage.getRefreshToken();
        if (rt != null) {
          try {
            final res = await ref.read(dioClientProvider).dio.post(
              ApiConstants.refresh,
              data: {'refreshToken': rt},
            );
            final newJwt = res.data['data']['jwt'] as String?;
            if (newJwt != null) {
              await storage.saveTokens(jwt: newJwt, refreshToken: rt);
              _connect();
            }
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _toggleOpen() async {
    final newStatus = !_isOpen;
    try {
      await ref.read(dioClientProvider).dio.put(
        ApiConstants.myRestaurantStatus,
        data: {'is_open': newStatus},
      );
      setState(() => _isOpen = newStatus);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    onOrdersReloadRequested = null;
    _socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        // Inherits AppBarTheme — transparent bg, adaptive foreground.
        actions: [
          // Open/Closed chip stays in AppBar — it's a primary action
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: GestureDetector(
              onTap: _toggleOpen,
              child: Chip(
                label: Text(
                  _isOpen ? 'OPEN' : 'CLOSED',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: _isOpen ? Colors.green : Colors.red,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
      drawer: _RestaurantDrawer(restaurantId: _restaurantId),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
              ? _buildLoadError()
              : _restaurantId == null &&
                  _pendingOrders.isEmpty &&
                  _activeOrders.isEmpty
              ? _buildSetupPrompt()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── New Orders section (pending_acceptance) ──────────────
                      if (_pendingOrders.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'New Orders',
                          count: _pendingOrders.length,
                          color: Colors.orange,
                          icon: Icons.notification_important,
                        ),
                        const SizedBox(height: 8),
                        ..._pendingOrders.map(
                          (order) => PendingAcceptanceOrderCard(
                            key: ValueKey(order.id),
                            order: order,
                            onAccepted: _load,
                            onRejected: _load,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Active Orders section ────────────────────────────────
                      if (_activeOrders.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'Active Orders',
                          count: _activeOrders.length,
                          color: Theme.of(context).colorScheme.primary,
                          icon: Icons.receipt_long,
                        ),
                        const SizedBox(height: 8),
                        ..._activeOrders.map(
                          (order) => _OrderCard(
                            key: ValueKey(order.id),
                            order: order,
                            onMarkReady: () async {
                              await ref
                                  .read(orderServiceProvider)
                                  .markReady(order.id);
                              await _load();
                            },
                            onCancelled: _load,
                          ),
                        ),
                      ],

                      if (_pendingOrders.isEmpty && _activeOrders.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 80),
                            child: Column(
                              children: [
                                Icon(Icons.inbox_outlined,
                                    size: 48, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('No orders right now',
                                    style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

// ── Section header widget ─────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Active order card (confirmed, ready_for_pickup, etc.) ─────────────────────
class _OrderCard extends ConsumerStatefulWidget {
  final OrderModel order;
  final VoidCallback onMarkReady;
  final VoidCallback onCancelled;

  const _OrderCard({
    super.key,
    required this.order,
    required this.onMarkReady,
    required this.onCancelled,
  });

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  static const List<String> _cancelReasons = [
    'Item unavailable',
    'Kitchen closed',
    'Too busy',
    'Ingredient ran out',
    'Other',
  ];

  Future<void> _showCancelDialog() async {
    String? selectedReason;
    bool isLoading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Cancel Order'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Please select a reason for cancellation:'),
                  const SizedBox(height: 8),
                  ..._cancelReasons.map(
                    (reason) => RadioListTile<String>(
                      title: Text(reason),
                      value: reason,
                      groupValue: selectedReason,
                      onChanged: isLoading
                          ? null
                          : (value) =>
                              setDialogState(() => selectedReason = value),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (selectedReason == null || isLoading)
                      ? null
                      : () async {
                          setDialogState(() => isLoading = true);
                          try {
                            await ref
                                .read(orderServiceProvider)
                                .cancelOrder(widget.order.id, selectedReason!);
                            if (dialogContext.mounted)
                              Navigator.of(dialogContext).pop();
                            widget.onCancelled();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Order cancelled')),
                              );
                            }
                          } catch (e) {
                            if (dialogContext.mounted)
                              Navigator.of(dialogContext).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirm',
                          style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final canCancel =
        order.status == 'confirmed' || order.status == 'ready_for_pickup';

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
                      fontWeight: FontWeight.bold, fontSize: 16),
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
            // Items list
            if (order.items.isNotEmpty) ...[
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${item.itemName} × ${item.quantity}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          'ETB ${(item.unitPrice * item.quantity).toStringAsFixed(2)}',
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )),
              const Divider(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Subtotal',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Text('ETB ${order.subtotal.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Delivery fee',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Text('ETB ${order.deliveryFee.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('ETB ${order.total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ] else
              Text('Total: ETB ${order.total.toStringAsFixed(2)}'),
            Text(
                'Time: ${order.createdAt.toLocal().toString().substring(11, 16)}'), // Prep timer — shown only for confirmed orders
            if (order.status == 'confirmed') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Preparing: ',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
                  ),
                  ElapsedTimer(
                    since: order.updatedAt ?? order.createdAt,
                    warnAfterMinutes: 10,
                    urgentAfterMinutes: 20,
                  ),
                  if (order.estimatedPrepTimeMinutes != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '/ ${order.estimatedPrepTimeMinutes}m target',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35)),
                    ),
                  ],
                ],
              ),
            ],
            if (order.status == 'confirmed') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.onMarkReady,
                  child: const Text('Mark Ready for Pickup'),
                ),
              ),
            ],
            if (canCancel) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _showCancelDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('Cancel Order'),
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

/// A thin public wrapper around the private [_OrderCard] widget, exposed
/// only for widget testing via @visibleForTesting.
class OrderCardTestWrapper extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onMarkReady;
  final VoidCallback onCancelled;

  const OrderCardTestWrapper({
    super.key,
    required this.order,
    required this.onMarkReady,
    required this.onCancelled,
  });

  @override
  Widget build(BuildContext context) {
    return _OrderCard(
      order: order,
      onMarkReady: onMarkReady,
      onCancelled: onCancelled,
    );
  }
}

// ── Restaurant Drawer ─────────────────────────────────────────────────────────

class _RestaurantDrawer extends ConsumerWidget {
  final String? restaurantId;
  const _RestaurantDrawer({this.restaurantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Drawer(
      // Surface color adapts to light/dark theme automatically
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 24,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4), width: 2),
                  ),
                  child: const Icon(Icons.storefront_outlined,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Restaurant Dashboard',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3),
                ),
                const SizedBox(height: 3),
                Text(
                  'Manage your restaurant',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12),
                ),
              ],
            ),
          ),

          // ── Nav items ─────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Operations section label
                _SectionLabel('Operations'),
                _DrawerItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Orders',
                  onTap: () => Navigator.pop(context),
                  isActive: true,
                ),
                _DrawerItem(
                  icon: Icons.restaurant_menu_outlined,
                  label: 'Menu Management',
                  onTap: () {
                    Navigator.pop(context);
                    if (restaurantId != null) {
                      context.push('/menu/$restaurantId');
                    } else {
                      context.push('/setup');
                    }
                  },
                ),
                _DrawerItem(
                  icon: Icons.delivery_dining_outlined,
                  label: 'My Riders',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/riders');
                  },
                ),

                const SizedBox(height: 4),
                _SectionLabel('Insights'),
                _DrawerItem(
                  icon: Icons.bar_chart_outlined,
                  label: 'Analytics',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/analytics');
                  },
                ),
                _DrawerItem(
                  icon: Icons.star_outline,
                  label: 'Customer Reviews',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/reviews');
                  },
                ),

                const SizedBox(height: 4),
                _SectionLabel('Restaurant Setup'),
                _DrawerItem(
                  icon: Icons.access_time_outlined,
                  label: 'Operating Hours',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/hours');
                  },
                ),
                _DrawerItem(
                  icon: Icons.campaign_outlined,
                  label: 'Promotional Banner',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/banner');
                  },
                ),
                _DrawerItem(
                  icon: Icons.photo_library_outlined,
                  label: 'Restaurant Images',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/images');
                  },
                ),

                const SizedBox(height: 4),
                const Divider(indent: 16, endIndent: 16, height: 16),
                _DrawerItem(
                  icon: Icons.person_outline,
                  label: 'Profile & Settings',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/profile');
                  },
                ),
              ],
            ),
          ),

          // ── Sign Out ──────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: _DrawerItem(
              icon: Icons.logout_outlined,
              label: 'Sign Out',
              color: Colors.red.shade600,
              onTap: () => ref.read(authProvider.notifier).logout(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: cs.onSurface.withValues(alpha: 0.4),
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool isActive;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.primary;
    final c = color ?? cs.onSurface.withValues(alpha: 0.75);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: isActive
            ? activeColor.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isActive
                        ? activeColor.withValues(alpha: 0.12)
                        : cs.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      size: 18,
                      color: isActive ? activeColor : c),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? activeColor : c,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
