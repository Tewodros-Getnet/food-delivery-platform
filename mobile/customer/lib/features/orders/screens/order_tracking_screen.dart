import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../core/constants/api_constants.dart';
import '../../../core/storage/secure_storage.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../../auth/services/auth_service.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});
  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  OrderModel? _order;
  double? _riderLat, _riderLon;
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
      final o = await ref.read(orderServiceProvider).getById(widget.orderId);
      setState(() {
        _order = o;
        _loading = false;
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
        setState(() =>
            _order = OrderModel.fromJson(d['order'] as Map<String, dynamic>));
      }
    });
    _socket!.on('rider:location_update', (data) {
      final d = data['data'] as Map<String, dynamic>;
      if (d['orderId'] == widget.orderId) {
        setState(() {
          _riderLat = (d['latitude'] as num).toDouble();
          _riderLon = (d['longitude'] as num).toDouble();
        });
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

    return Scaffold(
      appBar: AppBar(title: const Text('Track Order')),
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
          ]),
        ),
        // Live map with rider location — flutter_map + OpenStreetMap (no API key needed)
        if (_order!.status == 'picked_up' && _riderLat != null)
          SizedBox(
            height: 250,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(_riderLat!, _riderLon!),
                initialZoom: 15,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fooddelivery.customer',
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: LatLng(_riderLat!, _riderLon!),
                    width: 48,
                    height: 48,
                    child: const Icon(Icons.delivery_dining,
                        color: Colors.orange, size: 40),
                  ),
                ]),
              ],
            ),
          ),
        Expanded(child: _Timeline(status: _order!.status)),
        if (['confirmed', 'ready_for_pickup'].contains(_order!.status))
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

  String _statusLabel(String s) =>
      const {
        'pending_payment': 'Awaiting Payment',
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
