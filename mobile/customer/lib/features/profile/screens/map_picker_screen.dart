import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController _mapController = MapController();
  final _labelCtrl = TextEditingController();
  final _lineCtrl  = TextEditingController();

  // Default to Addis Ababa — replaced immediately by GPS on first frame
  LatLng _pinPosition = const LatLng(9.0192, 38.7525);

  // true while the initial GPS fix is in flight (shows full-screen overlay)
  bool _initialLocating = true;
  // true while the GPS button re-center is in flight (shows button spinner)
  bool _reLocating = false;

  String? _locationError;

  @override
  void initState() {
    super.initState();
    // Defer until the first frame so FlutterMap has mounted and registered
    // the MapController before we call move() on it.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _locateUser(initial: true));
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _lineCtrl.dispose();
    super.dispose();
  }

  Future<void> _locateUser({bool initial = false}) async {
    if (!mounted) return;
    setState(() {
      _locationError = null;
      if (initial) _initialLocating = true;
      else         _reLocating      = true;
    });

    try {
      // 1. Check GPS hardware is on
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationError =
            'GPS is turned off. Please enable location services.');
        return;
      }

      // 2. Check / request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() => _locationError =
            'Location permission denied. Tap the map to set a pin manually.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationError =
            'Location permission permanently denied. '
            'Please enable it in Settings → App permissions.');
        return;
      }

      // 3. Get position (customer app uses geolocator ^11 — desiredAccuracy API)
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _pinPosition = loc);
      _mapController.move(loc, 16);
    } catch (e) {
      if (mounted) {
        setState(() => _locationError =
            'Could not determine your location. '
            'Tap the map to set a pin manually.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _initialLocating = false;
          _reLocating      = false;
        });
      }
    }
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      _pinPosition   = point;
      _locationError = null;
    });
  }

  void _save() {
    if (_lineCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an address description'),
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'latitude':    _pinPosition.latitude,
      'longitude':   _pinPosition.longitude,
      'addressLine': _lineCtrl.text.trim(),
      'label': _labelCtrl.text.trim().isEmpty
          ? 'Home'
          : _labelCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Delivery Location'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pinPosition,
              initialZoom: 14,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.fooddelivery.customer',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pinPosition,
                    width: 48,
                    height: 56, // extra height so pin tip sits at the point
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_pin,
                      color: Colors.red,
                      size: 48,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Top hint pill ─────────────────────────────────────────────────
          if (!_initialLocating)
            Positioned(
              top: 12,
              left: 12,
              right: 68, // leave room for the GPS FAB
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6),
                  ],
                ),
                child: const Text(
                  'Tap the map or drag to set your delivery pin',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // ── GPS / re-center button ────────────────────────────────────────
          Positioned(
            top: 12,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'gps_customer',
              tooltip: 'Move to my location',
              onPressed: (_initialLocating || _reLocating)
                  ? null
                  : () => _locateUser(),
              backgroundColor: Colors.white,
              elevation: 2,
              child: (_initialLocating || _reLocating)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    )
                  : const Icon(Icons.my_location_rounded,
                      color: Colors.orange),
            ),
          ),

          // ── Full-screen loading overlay (initial GPS fix only) ────────────
          if (_initialLocating)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 16),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.orange),
                        const SizedBox(height: 14),
                        const Text(
                          'Finding your location…',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You can tap the map to set a pin manually',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Bottom sheet ──────────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(blurRadius: 10, color: Colors.black26)
                ],
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom:
                      MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Coordinates chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_pin,
                              color: Colors.orange, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${_pinPosition.latitude.toStringAsFixed(5)}, '
                            '${_pinPosition.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),

                    // Location error (if any)
                    if (_locationError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.amber.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 16, color: Colors.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _locationError!,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Address fields
                    TextField(
                      controller: _labelCtrl,
                      decoration: const InputDecoration(
                        labelText:
                            "Label (e.g. Home, Work, Friend's place)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _lineCtrl,
                      decoration: const InputDecoration(
                        labelText:
                            'Address description (street, building, area)',
                        border: OutlineInputBorder(),
                        prefixIcon:
                            Icon(Icons.edit_location_alt_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('Save Address',
                          style: TextStyle(
                              color: Colors.white, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
