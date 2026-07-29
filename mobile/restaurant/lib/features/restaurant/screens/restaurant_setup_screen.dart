import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import 'map_picker_screen.dart';

class RestaurantSetupScreen extends ConsumerStatefulWidget {
  const RestaurantSetupScreen({super.key});
  @override
  ConsumerState<RestaurantSetupScreen> createState() =>
      _RestaurantSetupScreenState();
}

class _RestaurantSetupScreenState extends ConsumerState<RestaurantSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  double? _latitude;
  double? _longitude;
  bool _isLoading = false;
  String? _error;

  static const _brandColor = Color(0xFF2E7D32);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const RestaurantMapPickerScreen()),
    );
    if (result != null) {
      setState(() {
        _latitude = result['latitude'] as double;
        _longitude = result['longitude'] as double;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      setState(
          () => _error = 'Please pick your restaurant location on the map');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(dioClientProvider).dio.post(
        ApiConstants.restaurants,
        data: {
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'address': _addressCtrl.text.trim(),
          'latitude': _latitude,
          'longitude': _longitude,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restaurant submitted for approval!'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/orders');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _field(String label, IconData icon, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _brandColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // ── Hero header ────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: _brandColor,
            foregroundColor: Colors.white,
            title: const Text('Register Restaurant',
                style: TextStyle(fontWeight: FontWeight.bold)),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                  ),
                ),
                child: const SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: 40),
                      Icon(Icons.storefront, size: 52, color: Colors.white),
                      SizedBox(height: 10),
                      Text('Tell us about your restaurant',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Form ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline,
                            color: Color(0xFF2E7D32), size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your restaurant will be reviewed by our team before going live.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF2E7D32)),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // Restaurant name
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          _field('Restaurant Name', Icons.storefront_outlined),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),

                    // Description
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _field(
                          'Description (optional)', Icons.description_outlined,
                          hint: 'e.g. Traditional Ethiopian cuisine...'),
                    ),
                    const SizedBox(height: 12),

                    // Address
                    TextFormField(
                      controller: _addressCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: _field(
                          'Address / Area Name', Icons.location_city_outlined,
                          hint: 'e.g. Bole, Addis Ababa'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Map picker
                    GestureDetector(
                      onTap: _pickLocation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _latitude != null
                              ? Colors.green.shade50
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _latitude != null
                                ? _brandColor
                                : Colors.grey.shade300,
                            width: _latitude != null ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Icon(
                            _latitude != null
                                ? Icons.location_on
                                : Icons.add_location_alt_outlined,
                            color: _latitude != null
                                ? _brandColor
                                : Colors.grey[500],
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _latitude != null
                                      ? 'Location selected ✓'
                                      : 'Pick Location on Map',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: _latitude != null
                                        ? _brandColor
                                        : Colors.grey[700],
                                  ),
                                ),
                                if (_latitude != null)
                                  Text(
                                    '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                        fontFamily: 'monospace'),
                                  )
                                else
                                  Text('Required — tap to open map',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500])),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: Colors.grey[400], size: 20),
                        ]),
                      ),
                    ),

                    // Error
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 13)),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Submit for Approval',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
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
