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
  final _lineCtrl = TextEditingController();

  // Default to Addis Ababa center
  LatLng _pinPosition = const LatLng(9.0192, 38.7525);
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _goToMyLocation();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _lineCtrl.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _pinPosition = loc);
      _mapController.move(loc, 16);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() => _pinPosition = point);
  }

  void _save() {
    if (_lineCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an address description')),
      );
      return;
    }
    Navigator.pop(context, {
      'latitude': _pinPosition.latitude,
      'longitude': _pinPosition.longitude,
      'addressLine': _lineCtrl.text.trim(),
      'label': _labelCtrl.text.trim().isEmpty ? 'Home' : _labelCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Delivery Location'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pinPosition,
              initialZoom: 14,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.fooddelivery.customer',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pinPosition,
                    width: 48,
                    height: 48,
                    child: const Icon(
                      Icons.location_pin,
                      color: Colors.red,
                      size: 48,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // GPS button
          Positioned(
            top: 12,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'gps',
              onPressed: _locating ? null : _goToMyLocation,
              backgroundColor: Colors.white,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: Colors.orange),
            ),
          ),

          // Hint text
          Positioned(
            top: 12,
            left: 12,
            right: 60,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Tap on the map or drag to set your delivery pin',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ),

          // Bottom sheet with fields
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black26)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Pin coordinates indicator
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_pin,
                            color: Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${_pinPosition.latitude.toStringAsFixed(5)}, '
                          '${_pinPosition.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: _labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Label (e.g. Home, Work, Friend\'s place)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _lineCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Address description (street, building, area)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit_location_alt_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Save Address',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
