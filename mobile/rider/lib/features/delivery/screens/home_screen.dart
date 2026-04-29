import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
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
  bool _restoringAvailability = true;
  bool _onDelivery = false;
  String? _activeOrderId;
  Map<String, dynamic>? _deliveryRequest;
  Map<String, dynamic>? _pendingInvitation; // pending restaurant invitation
  // Navigation coordinates set when rider accepts a delivery
  double? _restaurantLat, _restaurantLon;
  double? _customerLat, _customerLon;
  bool _pickedUp = false; // tracks whether pickup is confirmed
  Timer? _locationTimer;
  Timer? _requestTimer;
  io.Socket? _socket;
  double? _currentLat;
  double? _currentLon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Register callback FIRST so any pending request is delivered immediately
    onDeliveryRequestReceived = (data) {
      if (mounted) {
        setState(() => _deliveryRequest = {
              'orderId': data['orderId'],
              'restaurantName': data['restaurantName'] ?? 'Restaurant',
              'customerAddress': data['customerAddress'] ?? 'Customer',
              'deliveryFee': (data['deliveryFee'] is num)
                  ? (data['deliveryFee'] as num).toDouble()
                  : double.tryParse(data['deliveryFee']?.toString() ?? '0') ??
                      0.0,
              'estimatedDistance': (data['estimatedDistance'] is num)
                  ? (data['estimatedDistance'] as num).toDouble()
                  : double.tryParse(
                          data['estimatedDistance']?.toString() ?? '0') ??
                      0.0,
              'expiresAt': data['expiresAt'],
            });
        _requestTimer?.cancel();
        _requestTimer = Timer(const Duration(seconds: 60), () {
          if (_deliveryRequest != null) _declineDelivery();
        });
      }
    };

    // Consume any delivery request already stored before this screen mounted
    if (pendingDeliveryRequest != null) {
      final pending = pendingDeliveryRequest!;
      pendingDeliveryRequest = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onDeliveryRequestReceived?.call(pending);
      });
    }

    _connectSocket();
    _restoreAvailability();
    _checkInvitation();
  }

  Future<void> _checkInvitation() async {
    try {
      final res = await ref.read(riderServiceProvider).getPendingInvitation();
      if (mounted && res != null) {
        setState(() => _pendingInvitation = res);
      }
    } catch (_) {}
  }

  Future<void> _respondInvitation(bool accept) async {
    final id = _pendingInvitation?['id'] as String?;
    if (id == null) return;
    try {
      await ref.read(riderServiceProvider).respondInvitation(id, accept);
      setState(() => _pendingInvitation = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accept
              ? 'You joined the restaurant team!'
              : 'Invitation declined'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Restore persisted availability on app start / return from background
  Future<void> _restoreAvailability() async {
    final wasAvailable =
        await ref.read(secureStorageProvider).getAvailability();
    if (!mounted) return;
    setState(() {
      _isAvailable = wasAvailable;
      _restoringAvailability = false;
    });
    if (wasAvailable) {
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
      final payload = data['data'] as Map<String, dynamic>? ?? {};
      // Route through the same callback so data is normalized consistently
      onDeliveryRequestReceived?.call(payload);
      if (onDeliveryRequestReceived == null) {
        // Fallback: set directly if callback not registered yet
        setState(() => _deliveryRequest = payload);
        _requestTimer?.cancel();
        _requestTimer = Timer(const Duration(seconds: 60), () {
          if (_deliveryRequest != null) _declineDelivery();
        });
      }
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
    final result = await ref.read(riderServiceProvider).acceptDelivery(orderId);
    final nav = result?['navigation'] as Map<String, dynamic>?;
    final restaurant = nav?['restaurant'] as Map<String, dynamic>?;
    final delivery = nav?['delivery'] as Map<String, dynamic>?;
    debugPrint('Accept delivery nav: $nav');
    debugPrint(
        'Restaurant coords: lat=${restaurant?['latitude']}, lon=${restaurant?['longitude']}');
    debugPrint(
        'Customer coords: lat=${delivery?['latitude']}, lon=${delivery?['longitude']}');
    setState(() {
      _deliveryRequest = null;
      _onDelivery = true;
      _activeOrderId = orderId;
      _pickedUp = false;
      _restaurantLat = (restaurant?['latitude'] as num?)?.toDouble();
      _restaurantLon = (restaurant?['longitude'] as num?)?.toDouble();
      _customerLat = (delivery?['latitude'] as num?)?.toDouble();
      _customerLon = (delivery?['longitude'] as num?)?.toDouble();
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
    setState(() => _pickedUp = true);
  }

  Future<void> _confirmDelivery() async {
    if (_activeOrderId == null) return;
    await ref.read(riderServiceProvider).confirmDelivery(_activeOrderId!);
    setState(() {
      _onDelivery = false;
      _activeOrderId = null;
      _pickedUp = false;
      _restaurantLat = _restaurantLon = null;
      _customerLat = _customerLon = null;
    });
    _startLocationUpdates(interval: 30);
  }

  Future<void> _openNavigation(double lat, double lon) async {
    // Opens Google Maps app with turn-by-turn navigation — no API key needed
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fallback to geo: URI if Google Maps app not available
      final geoUri = Uri.parse('geo:$lat,$lon?q=$lat,$lon');
      await launchUrl(geoUri, mode: LaunchMode.externalApplication);
    }
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Rider Dashboard'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Earnings',
            onPressed: () => context.push('/earnings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(secureStorageProvider).saveAvailability(false);
              ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Availability toggle ──────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Availability',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isAvailable ? 'You are available' : 'You are offline',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _isAvailable,
                    onChanged: _restoringAvailability
                        ? null
                        : (_) => _toggleAvailability(),
                    activeColor: Colors.white,
                    activeTrackColor: Colors.white.withOpacity(0.4),
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white24,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Pending invitation card ──────────────────────────────────
            if (_pendingInvitation != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.shade200),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.store_outlined,
                              color: Color(0xFF2E7D32), size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Restaurant Invitation',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${_pendingInvitation!['restaurant_name']} wants you to join their delivery team.',
                      style: const TextStyle(fontSize: 14),
                    ),
                    if ((_pendingInvitation!['restaurant_address'] as String?)
                            ?.isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 4),
                      Text(
                        _pendingInvitation!['restaurant_address'] as String,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _respondInvitation(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Accept',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _respondInvitation(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Decline'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Delivery request card ────────────────────────────────────
            if (_deliveryRequest != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Blue gradient header
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.delivery_dining,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 10),
                          const Text(
                            'New Delivery Request',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // White body
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow(
                              Icons.restaurant_outlined,
                              _deliveryRequest!['restaurantName'] ??
                                  'Restaurant'),
                          const SizedBox(height: 8),
                          _detailRow(
                              Icons.location_on_outlined,
                              _deliveryRequest!['customerAddress'] ??
                                  'Customer'),
                          const SizedBox(height: 8),
                          _detailRow(Icons.payments_outlined,
                              'ETB ${_deliveryRequest!['deliveryFee'] ?? 0}'),
                          const SizedBox(height: 8),
                          _detailRow(
                            Icons.straighten_outlined,
                            '${(_deliveryRequest!['estimatedDistance'] as num?)?.toStringAsFixed(1) ?? '?'} km',
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _acceptDelivery,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Accept',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _declineDelivery,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Decline'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Active delivery card ─────────────────────────────────────────
            if (_onDelivery && _activeOrderId != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Orange accent header
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.local_shipping_outlined,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Active Delivery',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Order #${_activeOrderId!.substring(0, 8).toUpperCase()}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline,
                                color: Colors.white),
                            tooltip: 'Chat with customer',
                            onPressed: () {
                              final userId =
                                  ref.read(authProvider).user?.id ?? '';
                              context.push(
                                '/chat/${_activeOrderId!}',
                                extra: userId,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    // White body
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Map in rounded container
                          Container(
                            height: 180,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
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
                                  userAgentPackageName:
                                      'com.fooddelivery.rider',
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
                          const SizedBox(height: 14),
                          // Navigate button — full-width with icon
                          if (!_pickedUp)
                            SizedBox(
                              width: double.infinity,
                              child: _restaurantLat != null
                                  ? ElevatedButton.icon(
                                      onPressed: () => _openNavigation(
                                          _restaurantLat!, _restaurantLon!),
                                      icon: const Icon(Icons.navigation,
                                          color: Colors.white),
                                      label: const Text(
                                          'Navigate to Restaurant',
                                          style:
                                              TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1565C0),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    )
                                  : const Text(
                                      'Restaurant location unavailable',
                                      style: TextStyle(color: Colors.grey),
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                          if (_pickedUp)
                            SizedBox(
                              width: double.infinity,
                              child: _customerLat != null
                                  ? ElevatedButton.icon(
                                      onPressed: () => _openNavigation(
                                          _customerLat!, _customerLon!),
                                      icon: const Icon(Icons.navigation,
                                          color: Colors.white),
                                      label: const Text('Navigate to Customer',
                                          style:
                                              TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1565C0),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    )
                                  : const Text(
                                      'Customer location unavailable',
                                      style: TextStyle(color: Colors.grey),
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                          const SizedBox(height: 10),
                          // Action button — full-width
                          if (!_pickedUp)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _confirmPickup,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade600,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text('Confirm Pickup',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          if (_pickedUp)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _confirmDelivery,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text('Confirm Delivery',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Offline empty state ──────────────────────────────────────────
            if (!_isAvailable && !_onDelivery)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 64),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.delivery_dining,
                          size: 64, color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'You\'re offline',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Go online to start earning',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 14),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Small icon + text row used in the delivery request detail body.
  Widget _detailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
