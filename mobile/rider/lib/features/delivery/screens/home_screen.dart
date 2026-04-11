import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'dart:async';
import '../../../core/constants/api_constants.dart';
import '../../../core/storage/secure_storage.dart';
import '../services/rider_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/fcm_service.dart';

class RiderHomeScreen extends ConsumerStatefulWidget {
  const RiderHomeScreen({super.key});
  @override
  ConsumerState<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends ConsumerState<RiderHomeScreen>
    with WidgetsBindingObserver {
  bool _isAvailable = false;
  bool _onDelivery = false;
  String? _activeOrderId;
  Map<String, dynamic>? _deliveryRequest;
  Timer? _locationTimer;
  Timer? _requestTimer;
  io.Socket? _socket;
  double? _currentLat;
  double? _currentLon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectSocket();
    _restoreAvailability();
    // Register FCM callback so delivery requests work even when app is backgrounded
    onDeliveryRequestReceived = (data) {
      if (mounted) {
        setState(() => _deliveryRequest = {
              'orderId': data['orderId'],
              'restaurantName': data['restaurantName'] ?? 'Restaurant',
              'customerAddress': data['customerAddress'] ?? 'Customer',
              'deliveryFee': double.tryParse(data['deliveryFee'] ?? '0') ?? 0,
              'estimatedDistance':
                  double.tryParse(data['estimatedDistance'] ?? '0') ?? 0,
              'expiresAt': data['expiresAt'],
            });
        _requestTimer?.cancel();
        _requestTimer = Timer(const Duration(seconds: 60), () {
          if (_deliveryRequest != null) _declineDelivery();
        });
      }
    };
  }

  // Restore persisted availability on app start / return from background
  Future<void> _restoreAvailability() async {
    final wasAvailable =
        await ref.read(secureStorageProvider).getAvailability();
    if (wasAvailable && mounted) {
      setState(() => _isAvailable = true);
      final locationOk = await _sendLocationNow();
      if (locationOk) {
        _startLocationUpdates(interval: 30);
      }
    }
  }

  // Called when app comes back to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isAvailable) {
      _sendLocationNow(); // return value intentionally ignored here — best effort on resume
      _connectSocket();
    }
  }

  Future<bool> _sendLocationNow() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission permanently denied. '
                'Please enable it in app settings to go available.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return false;
      }
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required to go available.'),
            ),
          );
        }
        return false;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return false;
      setState(() {
        _currentLat = pos.latitude;
        _currentLon = pos.longitude;
      });
      final availability = _onDelivery ? 'on_delivery' : 'available';
      await ref
          .read(riderServiceProvider)
          .updateLocation(pos.latitude, pos.longitude, availability);
      return true;
    } catch (e) {
      debugPrint('Location error: $e');
      return false;
    }
  }

  Future<void> _connectSocket() async {
    _socket?.disconnect();
    _socket?.dispose();

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
    _socket!.on('delivery:request', (data) {
      setState(() => _deliveryRequest = data['data'] as Map<String, dynamic>);
      // Auto-decline after 60 seconds
      _requestTimer = Timer(const Duration(seconds: 60), () {
        if (_deliveryRequest != null) _declineDelivery();
      });
    });
    _socket!.on('connect_error', (err) async {
      debugPrint('Rider socket connect_error: $err');
      // If auth error, refresh token and reconnect
      final errStr = err.toString();
      if (errStr.contains('Invalid token') ||
          errStr.contains('Authentication')) {
        final rt = await ref.read(secureStorageProvider).getRefreshToken();
        if (rt != null) {
          try {
            final res = await ref.read(riderServiceProvider).refreshToken(rt);
            if (res != null) {
              await ref
                  .read(secureStorageProvider)
                  .saveTokens(jwt: res, refreshToken: rt);
              _connectSocket(); // reconnect with fresh token
            }
          } catch (_) {}
        }
      }
    });
    _socket!.on('connect', (_) => debugPrint('Rider socket connected ✅'));
    _socket!.on('disconnect',
        (reason) => debugPrint('Rider socket disconnected: $reason'));
  }

  Future<void> _toggleAvailability() async {
    final newStatus = _isAvailable ? 'offline' : 'available';
    try {
      await ref.read(riderServiceProvider).setAvailability(newStatus);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update availability: $e')),
        );
      }
      return; // don't update state if API call failed
    }

    final nowAvailable = !_isAvailable;
    setState(() => _isAvailable = nowAvailable);

    // Persist the new state
    await ref.read(secureStorageProvider).saveAvailability(nowAvailable);

    if (nowAvailable) {
      // Send location immediately so dispatch finds this rider right away
      final locationOk = await _sendLocationNow();
      if (!locationOk) {
        // Location permission denied — roll back availability
        try {
          await ref.read(riderServiceProvider).setAvailability('offline');
        } catch (_) {}
        setState(() => _isAvailable = false);
        await ref.read(secureStorageProvider).saveAvailability(false);
        return;
      }
      _startLocationUpdates(interval: 30);
    } else {
      _locationTimer?.cancel();
    }
  }

  void _startLocationUpdates({required int interval}) {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      if (_isAvailable)
        await _sendLocationNow(); // best-effort, return value ignored
    });
  }

  Future<void> _acceptDelivery() async {
    final orderId = _deliveryRequest?['orderId'] as String?;
    if (orderId == null) return;
    _requestTimer?.cancel();
    await ref.read(riderServiceProvider).acceptDelivery(orderId);
    setState(() {
      _deliveryRequest = null;
      _onDelivery = true;
      _activeOrderId = orderId;
    });
    _startLocationUpdates(interval: 10);
  }

  Future<void> _declineDelivery() async {
    final orderId = _deliveryRequest?['orderId'] as String?;
    if (orderId == null) return;
    _requestTimer?.cancel();
    await ref.read(riderServiceProvider).declineDelivery(orderId);
    setState(() => _deliveryRequest = null);
  }

  Future<void> _confirmPickup() async {
    if (_activeOrderId == null) return;
    await ref.read(riderServiceProvider).confirmPickup(_activeOrderId!);
    setState(() {});
  }

  Future<void> _confirmDelivery() async {
    if (_activeOrderId == null) return;
    await ref.read(riderServiceProvider).confirmDelivery(_activeOrderId!);
    setState(() {
      _onDelivery = false;
      _activeOrderId = null;
    });
    _startLocationUpdates(interval: 30);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    onDeliveryRequestReceived = null;
    _locationTimer?.cancel();
    _requestTimer?.cancel();
    _socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Dashboard'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // Clear availability on logout
              await ref.read(secureStorageProvider).saveAvailability(false);
              ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Availability toggle
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Availability',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(
                          _isAvailable
                              ? 'You are available'
                              : 'You are offline',
                          style: TextStyle(
                              color: _isAvailable ? Colors.green : Colors.grey),
                        ),
                      ],
                    ),
                    Switch(
                      value: _isAvailable,
                      onChanged: (_) => _toggleAvailability(),
                      activeThumbColor: const Color(0xFF1565C0),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Delivery request card
            if (_deliveryRequest != null)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('New Delivery Request!',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1565C0))),
                      const SizedBox(height: 8),
                      Text(
                          'From: ${_deliveryRequest!['restaurantName'] ?? 'Restaurant'}'),
                      Text(
                          'To: ${_deliveryRequest!['customerAddress'] ?? 'Customer'}'),
                      Text('Fee: ETB ${_deliveryRequest!['deliveryFee'] ?? 0}'),
                      Text(
                          'Distance: ${(_deliveryRequest!['estimatedDistance'] as num?)?.toStringAsFixed(1) ?? '?'} km'),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _acceptDelivery,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green),
                            child: const Text('Accept',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _declineDelivery,
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red)),
                            child: const Text('Decline'),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),

            // Active delivery card
            if (_onDelivery && _activeOrderId != null)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Active Delivery',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Order: ${_activeOrderId!.substring(0, 8)}...'),
                      const SizedBox(height: 12),
                      Container(
                        height: 160,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8)),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                                _currentLat ?? 9.03, _currentLon ?? 38.74),
                            initialZoom: 14,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.fooddelivery.rider',
                            ),
                            if (_currentLat != null)
                              MarkerLayer(markers: [
                                Marker(
                                  point: LatLng(_currentLat!, _currentLon!),
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.delivery_dining,
                                      color: Color(0xFF1565C0), size: 36),
                                ),
                              ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _confirmPickup,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange),
                            child: const Text('Confirm Pickup',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _confirmDelivery,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green),
                            child: const Text('Confirm Delivery',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),

            if (!_isAvailable && !_onDelivery)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delivery_dining, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Toggle availability to start receiving orders',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
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
