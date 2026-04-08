import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import 'map_picker_screen.dart';

class AddressesScreen extends ConsumerStatefulWidget {
  const AddressesScreen({super.key});
  @override
  ConsumerState<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends ConsumerState<AddressesScreen> {
  List<dynamic> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await ref.read(dioClientProvider).dio.get(ApiConstants.addresses);
      setState(() {
        _addresses = res.data['data'] as List<dynamic>;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteAddress(String id) async {
    await ref
        .read(dioClientProvider)
        .dio
        .delete('${ApiConstants.addresses}/$id');
    await _load();
  }

  Future<void> _openMapPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (result == null) return;

    try {
      await ref.read(dioClientProvider).dio.post(ApiConstants.addresses, data: {
        'addressLine': result['addressLine'],
        'latitude': result['latitude'],
        'longitude': result['longitude'],
        'label': result['label'],
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving address: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Addresses')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openMapPicker,
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _addresses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_off,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No saved addresses',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _openMapPicker,
                        icon: const Icon(Icons.add_location_alt),
                        label: const Text('Add Address'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _addresses.length,
                  itemBuilder: (ctx, i) {
                    final a = _addresses[i] as Map<String, dynamic>;
                    return ListTile(
                      leading:
                          const Icon(Icons.location_on, color: Colors.orange),
                      title: Text(a['label'] as String? ?? 'Address'),
                      subtitle: Text(a['address_line'] as String),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (a['is_default'] == true)
                            const Chip(
                                label: Text('Default',
                                    style: TextStyle(fontSize: 11))),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteAddress(a['id'] as String),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
