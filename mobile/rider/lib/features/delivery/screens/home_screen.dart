import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:ui' as ui;
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
  // Navigation coordinates set when rider accepts a delivery
  double? _restaurantLat, _restaurantLon;
  double? _customerLat, _customerLon;
  bool _pickedUp = false; // tracks whether pickup is confirmed
  Timer? _locationTimer;
  Timer? _requestTimer;
  io.Socket? _socket;
  double? _currentLat;
  double? _currentLon;
  final MapController _mapController = MapController();

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
        // Use server-provided expiresAt so the timer matches dispatch config.
        // Fall back to 60s if the field is missing or unparseable.
        Duration timeoutDuration = const Duration(seconds: 60);
        final expiresAtStr = data['expiresAt'] as String?;
        if (expiresAtStr != null) {
          final expiresAt = DateTime.tryParse(expiresAtStr);
          if (expiresAt != null) {
            final remaining = expiresAt.difference(DateTime.now());
            if (remaining.inSeconds > 0) timeoutDuration = remaining;
          }
        }
        _requestTimer = Timer(timeoutDuration, () {
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
  }

  Future<void> _restoreAvailability() async {
    final storage = ref.read(secureStorageProvider);
    final wasAvailable = await storage.getAvailability();
    final deliveryState = await storage.getDeliveryState();

    if (!mounted) return;
    // Single setState so the toggle never renders an intermediate state
    setState(() {
      _isAvailable = wasAvailable;
      _restoringAvailability = false;
      if (deliveryState != null) {
        _onDelivery     = true;
        _activeOrderId  = deliveryState['orderId']       as String;
        _restaurantLat  = deliveryState['restaurantLat'] as double;
        _restaurantLon  = deliveryState['restaurantLon'] as double;
        _customerLat    = deliveryState['customerLat']   as double;
        _customerLon    = deliveryState['customerLon']   as double;
        _pickedUp       = deliveryState['pickedUp']      as bool;
      }
    });

    if (wasAvailable) {
      final locationOk = await _sendLocationNow();
      if (locationOk) {
        _startLocationUpdates(interval: _onDelivery ? 10 : 30);
      } else {
        // Location failed — mark offline so toggle reflects reality
        setState(() => _isAvailable = false);
        await storage.saveAvailability(false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Best-effort location refresh on resume
      if (_isAvailable) _sendLocationNow();
      // Only reconnect if the socket actually dropped
      if (_socket?.connected != true) _connectSocket();
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
    // Don't reconnect if already connected — prevents duplicate event handlers
    // that cause delivery requests to fire twice and the toggle to appear to flip.
    if (_socket?.connected == true) return;

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
        Duration timeoutDuration = const Duration(seconds: 60);
        final expiresAtStr = payload['expiresAt'] as String?;
        if (expiresAtStr != null) {
          final expiresAt = DateTime.tryParse(expiresAtStr);
          if (expiresAt != null) {
            final remaining = expiresAt.difference(DateTime.now());
            if (remaining.inSeconds > 0) timeoutDuration = remaining;
          }
        }
        _requestTimer = Timer(timeoutDuration, () {
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
              await ref.read(secureStorageProvider).saveTokens(
                jwt: res['jwt']!,
                refreshToken: res['refreshToken']!,
              );
              _connectSocket(); // reconnect with fresh token
            }
          } catch (_) {}
        }
      }
    });
    _socket!.on('connect', (_) => debugPrint('Rider socket connected ✅'));
    _socket!.on('disconnect',
        (reason) => debugPrint('Rider socket disconnected: $reason'));

    // Real-time invitation from restaurant — delegate to authProvider
    // so the router can navigate to /invitation automatically.
    _socket!.on('rider:invitation', (data) {
      if (!mounted) return;
      final payload = data['data'] as Map<String, dynamic>? ?? {};
      if (payload.isEmpty) return;
      ref.read(authProvider.notifier).onInvitationReceived(payload);
    });
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

    // Parse coordinates robustly — values come as num (double/int) from JSON,
    // not as String, so we always go through num first.
    double? rLat, rLon, cLat, cLon;
    if (restaurant != null) {
      rLat = (restaurant['latitude'] as num?)?.toDouble();
      rLon = (restaurant['longitude'] as num?)?.toDouble();
    }
    if (delivery != null) {
      cLat = (delivery['latitude'] as num?)?.toDouble();
      cLon = (delivery['longitude'] as num?)?.toDouble();
    }

    setState(() {
      _deliveryRequest = null;
      _onDelivery = true;
      _activeOrderId = orderId;
      _pickedUp = false;
      _restaurantLat = rLat;
      _restaurantLon = rLon;
      _customerLat = cLat;
      _customerLon = cLon;
    });

    // Persist so state survives app restart
    if (rLat != null && rLon != null && cLat != null && cLon != null) {
      await ref.read(secureStorageProvider).saveDeliveryState(
        orderId: orderId,
        restaurantLat: rLat,
        restaurantLon: rLon,
        customerLat: cLat,
        customerLon: cLon,
        pickedUp: false,
      );
    }

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
    // Persist the updated pickedUp flag so it survives app restart
    await ref.read(secureStorageProvider).updateDeliveryPickedUp(true);
  }

  Future<void> _confirmDelivery() async {
    if (_activeOrderId == null) return;
    await ref.read(riderServiceProvider).confirmDelivery(_activeOrderId!);
    // Clear persisted delivery state — delivery is complete
    await ref.read(secureStorageProvider).clearDeliveryState();
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
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Tana Driver'),
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
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  ],
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
                        style: const TextStyle(
                          color: Colors.white70,
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
                    activeTrackColor: Colors.white.withValues(alpha: 0.4),
                    inactiveThumbColor: Colors.white70,
                    inactiveTrackColor: Colors.white24,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Delivery request card ────────────────────────────────────
            if (_deliveryRequest != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand gradient header
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: const Row(
                        children: [
                          Icon(Icons.delivery_dining,
                              color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Text(
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
                    // Body
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
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Accept',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
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
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Orange accent header (semantic — means "in progress")
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFE65100), // deep orange — stands out in both modes
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
                    // Body
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Map in rounded container
                          Container(
                            height: 220,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                            ),
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _pickedUp
                                    ? LatLng(
                                        _customerLat ?? _currentLat ?? 9.03,
                                        _customerLon ?? _currentLon ?? 38.74)
                                    : LatLng(
                                        _restaurantLat ?? _currentLat ?? 9.03,
                                        _restaurantLon ?? _currentLon ?? 38.74),
                                initialZoom: 14,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'com.fooddelivery.rider',
                                ),
                                MarkerLayer(
                                  markers: [
                                    // Rider's current position
                                    if (_currentLat != null)
                                      Marker(
                                        point: LatLng(
                                            _currentLat!, _currentLon!),
                                        width: 40,
                                        height: 40,
                                        child: Icon(
                                            Icons.delivery_dining,
                                            color: Theme.of(context).colorScheme.primary,
                                            size: 36),
                                      ),
                                    // Restaurant pin — shown before pickup
                                    if (!_pickedUp && _restaurantLat != null)
                                      Marker(
                                        point: LatLng(
                                            _restaurantLat!, _restaurantLon!),
                                        width: 44,
                                        height: 44,
                                        child: const _MapPin(
                                          icon: Icons.restaurant,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    // Customer pin — shown after pickup
                                    if (_pickedUp && _customerLat != null)
                                      Marker(
                                        point: LatLng(
                                            _customerLat!, _customerLon!),
                                        width: 44,
                                        height: 44,
                                        child: const _MapPin(
                                          icon: Icons.home,
                                          color: Colors.green,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Navigate button
                          if (!_pickedUp)
                            SizedBox(
                              width: double.infinity,
                              child: _restaurantLat != null
                                  ? ElevatedButton.icon(
                                      onPressed: () => _openNavigation(
                                          _restaurantLat!, _restaurantLon!),
                                      icon: const Icon(Icons.navigation),
                                      label: const Text('Navigate to Restaurant'),
                                      style: ElevatedButton.styleFrom(
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    )
                                  : Text(
                                      'Restaurant location unavailable',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.45)),
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
                                      icon: const Icon(Icons.navigation),
                                      label: const Text('Navigate to Customer'),
                                      style: ElevatedButton.styleFrom(
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    )
                                  : Text(
                                      'Customer location unavailable',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.45)),
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                          const SizedBox(height: 10),
                          // Action button
                          if (!_pickedUp)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _confirmPickup,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade700,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text('Confirm Pickup',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          if (_pickedUp)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _confirmDelivery,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text('Confirm Delivery',
                                    style: TextStyle(
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
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.delivery_dining,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.35)),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'You\'re offline',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Go online to start earning',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                          fontSize: 14),
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
        Icon(icon,
            size: 16,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.55)),
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

/// Coloured pin marker used on the delivery map.
class _MapPin extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MapPin({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        // Pin tail
        CustomPaint(
          size: const Size(12, 6),
          painter: _PinTailPainter(color: color),
        ),
      ],
    );
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  const _PinTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PinTailPainter old) => old.color != color;
}
