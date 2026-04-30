import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'dart:math' as math;
import '../../../core/constants/api_constants.dart';
import '../../../core/storage/secure_storage.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/providers/auth_provider.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});
  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen>
    with WidgetsBindingObserver {
  OrderModel? _order;
  double? _riderLat, _riderLon;
  double? _destLat, _destLon; // customer delivery coordinates from socket
  bool _loading = true;
  io.Socket? _socket;
  String? _searchingRiderMessage;
  bool _nearbyNotified = false; // prevent repeated "rider is nearby" messages

  // Haversine distance in km (pure Dart, no external package needed)
  static double _distanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // ETA label based on rider's current distance to customer at 30 km/h
  String? _liveEtaLabel() {
    if (_riderLat == null || _destLat == null) return null;
    final distKm = _distanceKm(_riderLat!, _riderLon!, _destLat!, _destLon!);
    final mins = (distKm / 30 * 60).ceil();
    if (mins < 1) return 'Arriving now';
    return '~$mins min away';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh order status and reconnect socket when app comes back to foreground
      _load();
      _connect();
    }
  }

  Future<void> _load() async {
    try {
      final o = await ref.read(orderServiceProvider).getById(widget.orderId);
      setState(() {
        _order = o;
        _loading = false;
        // Seed destination from order so map is ready before first location update
        if (o.deliveryLat != null && _destLat == null) {
          _destLat = o.deliveryLat;
          _destLon = o.deliveryLon;
        }
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    final token = await ref.read(secureStorageProvider).getJwt();
    if (token == null) return;
    _socket?.disconnect();
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
            .build());
    _socket!.on('order:status_changed', (data) {
      final d = data['data'] as Map<String, dynamic>;
      if (d['orderId'] == widget.orderId) {
        final updatedOrder =
            OrderModel.fromJson(d['order'] as Map<String, dynamic>);
        final previousStatus = _order?.status;
        setState(() {
          _order = updatedOrder;
          _searchingRiderMessage = null;
        });
        // Show specific message when order is cancelled from pending_acceptance
        if (previousStatus == 'pending_acceptance' &&
            updatedOrder.status == 'cancelled' &&
            mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your order was not accepted by the restaurant. A refund has been initiated.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 6),
            ),
          );
        }
      }
    });
    _socket!.on('order:searching_rider', (data) {
      final d = data['data'] as Map<String, dynamic>;
      if (d['orderId'] == widget.orderId) {
        setState(() => _searchingRiderMessage =
            'Looking for a rider... (attempt ${d['retryCount']}/${d['maxRetries']})');
      }
    });
    _socket!.on('rider:location_update', (data) {
      final d = data['data'] as Map<String, dynamic>;
      if (d['orderId'] == widget.orderId) {
        final newLat = (d['latitude'] as num).toDouble();
        final newLon = (d['longitude'] as num).toDouble();
        final dstLat = (d['destinationLat'] as num?)?.toDouble();
        final dstLon = (d['destinationLon'] as num?)?.toDouble();
        setState(() {
          _riderLat = newLat;
          _riderLon = newLon;
          if (dstLat != null) _destLat = dstLat;
          if (dstLon != null) _destLon = dstLon;
        });
        // Show "rider is nearby" snackbar once when within 500m
        if (!_nearbyNotified && _destLat != null) {
          final dist = _distanceKm(newLat, newLon, _destLat!, _destLon!);
          if (dist <= 0.5) {
            _nearbyNotified = true;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🛵 Your rider is less than 500m away!'),
                  backgroundColor: Colors.deepOrange,
                  duration: Duration(seconds: 5),
                ),
              );
            }
          }
        }
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
            final newJwt = await ref.read(authServiceProvider).refreshToken(rt);
            if (newJwt != null) {
              await storage.saveTokens(jwt: newJwt, refreshToken: rt);
              _connect(); // reconnect with fresh token
            }
          } catch (_) {}
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_order == null)
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('Order not found')));

    final currentUserId = ref.read(authProvider).user?.id;
    final showChat = ['rider_assigned', 'picked_up'].contains(_order!.status);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Order'),
        actions: [
          if (showChat && currentUserId != null)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Chat with rider',
              onPressed: () => context.push(
                '/order/${widget.orderId}/chat',
                extra: currentUserId,
              ),
            ),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.orange.shade50,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_statusLabel(_order!.status),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_order!.statusMessage,
                style: TextStyle(color: Colors.grey[700])),
            // Pending acceptance: show spinner
            if (_order!.status == 'pending_acceptance') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'The restaurant is reviewing your order...',
                    style: TextStyle(color: Colors.orange[700], fontSize: 13),
                  ),
                ],
              ),
            ],
            if (_order!.estimatedDeliveryTime != null &&
                !['delivered', 'cancelled'].contains(_order!.status)) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.access_time,
                    size: 14, color: Colors.deepOrange),
                const SizedBox(width: 4),
                Text(
                  // Show live distance-based ETA when rider is moving,
                  // fall back to the server-calculated ETA otherwise
                  _order!.status == 'picked_up' && _liveEtaLabel() != null
                      ? _liveEtaLabel()!
                      : _etaLabel(_order!.estimatedDeliveryTime!),
                  style: const TextStyle(
                      color: Colors.deepOrange,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ],
            // Show live ETA even if no server ETA was set
            if (_order!.estimatedDeliveryTime == null &&
                _order!.status == 'picked_up' &&
                _liveEtaLabel() != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.access_time,
                    size: 14, color: Colors.deepOrange),
                const SizedBox(width: 4),
                Text(
                  _liveEtaLabel()!,
                  style: const TextStyle(
                      color: Colors.deepOrange,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ],
            if (_searchingRiderMessage != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_searchingRiderMessage!,
                      style:
                          const TextStyle(color: Colors.orange, fontSize: 13)),
                ),
              ]),
            ],
          ]),
        ),
        // Order details: restaurant name + item list
        if (_order!.restaurantName != null || _order!.items.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_order!.restaurantName != null) ...[
                  Row(children: [
                    const Icon(Icons.restaurant,
                        size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                      _order!.restaurantName!,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ]),
                  const SizedBox(height: 8),
                ],
                if (_order!.items.isNotEmpty) ...[
                  ..._order!.items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey[700]),
                                ),
                              ],
                            ),
                            if (item.modifiersSummary.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8, top: 1),
                                child: Text(
                                  item.modifiersSummary,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.black45),
                                ),
                              ),
                          ],
                        ),
                      )),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Delivery fee',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text('ETB ${_order!.deliveryFee.toStringAsFixed(2)}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('ETB ${_order!.total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        // Live map — shown from rider_assigned onwards (not just picked_up)
        if (['rider_assigned', 'picked_up'].contains(_order!.status) &&
            _riderLat != null)
          SizedBox(
            height: 260,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(_riderLat!, _riderLon!),
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fooddelivery.customer',
                ),
                // Polyline: rider → customer destination
                if (_destLat != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [
                          LatLng(_riderLat!, _riderLon!),
                          LatLng(_destLat!, _destLon!),
                        ],
                        color: Colors.deepOrange,
                        strokeWidth: 3.5,
                        isDotted: true,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    // Rider marker
                    Marker(
                      point: LatLng(_riderLat!, _riderLon!),
                      width: 48,
                      height: 48,
                      child: const Icon(Icons.delivery_dining,
                          color: Colors.orange, size: 40),
                    ),
                    // Restaurant marker
                    if (_order!.restaurantLat != null)
                      Marker(
                        point: LatLng(
                            _order!.restaurantLat!, _order!.restaurantLon!),
                        width: 36,
                        height: 36,
                        child: const Icon(Icons.restaurant,
                            color: Color(0xFF2E7D32), size: 28),
                      ),
                    // Customer / destination marker
                    if (_destLat != null)
                      Marker(
                        point: LatLng(_destLat!, _destLon!),
                        width: 36,
                        height: 36,
                        child: const Icon(Icons.location_on,
                            color: Colors.red, size: 32),
                      ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(child: _Timeline(status: _order!.status)),
        if (['confirmed', 'ready_for_pickup', 'pending_acceptance']
            .contains(_order!.status))
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: () => _confirmCancel(context),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(double.infinity, 48)),
              child: const Text('Cancel Order'),
            ),
          ),
        if (_order!.status == 'delivered')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                '/order/${widget.orderId}/rate',
                extra: {
                  'restaurantName': _order!.restaurantName,
                  'riderName': null,
                },
              ),
              icon: const Icon(Icons.star_rounded, color: Colors.white),
              label: const Text('Rate Your Order',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
      ]),
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Cancel Order'),
              content: const Text('Are you sure?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('No')),
                TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ref
                          .read(orderServiceProvider)
                          .cancel(widget.orderId);
                      await _load();
                    },
                    child: const Text('Yes, Cancel',
                        style: TextStyle(color: Colors.red))),
              ],
            ));
  }

  String _etaLabel(DateTime eta) {
    final now = DateTime.now();
    final diff = eta.difference(now);
    if (diff.isNegative) return 'Arriving soon';
    final mins = diff.inMinutes;
    if (mins < 1) return 'Arriving now';
    return 'Estimated delivery: ~$mins min';
  }

  String _statusLabel(String s) =>
      const {
        'pending_payment': 'Awaiting Payment',
        'pending_acceptance': 'Waiting for Restaurant',
        'confirmed': 'Order Confirmed',
        'ready_for_pickup': 'Food Ready',
        'rider_assigned': 'Rider Assigned',
        'picked_up': 'On the Way',
        'delivered': 'Delivered',
        'cancelled': 'Cancelled',
      }[s] ??
      s;
}

class _Timeline extends StatelessWidget {
  final String status;
  const _Timeline({required this.status});
  @override
  Widget build(BuildContext context) {
    final steps = [
      'pending_acceptance',
      'confirmed',
      'ready_for_pickup',
      'rider_assigned',
      'picked_up',
      'delivered'
    ];
    final idx = steps.indexOf(status);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: steps.length,
      itemBuilder: (ctx, i) {
        final done = i <= idx;
        return Row(children: [
          Column(children: [
            CircleAvatar(
                radius: 12,
                backgroundColor: done ? Colors.orange : Colors.grey[300],
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null),
            if (i < steps.length - 1)
              Container(
                  width: 2,
                  height: 40,
                  color: done ? Colors.orange : Colors.grey[300]),
          ]),
          const SizedBox(width: 12),
          Text(
              const {
                    'pending_acceptance': 'Restaurant Confirming',
                    'confirmed': 'Order Confirmed',
                    'ready_for_pickup': 'Food Ready',
                    'rider_assigned': 'Rider Assigned',
                    'picked_up': 'Picked Up',
                    'delivered': 'Delivered'
                  }[steps[i]] ??
                  steps[i],
              style: TextStyle(
                  fontWeight: done ? FontWeight.bold : FontWeight.normal,
                  color: done ? Colors.black : Colors.grey)),
        ]);
      },
    );
  }
}
