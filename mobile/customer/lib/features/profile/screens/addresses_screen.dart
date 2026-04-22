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
  List<Map<String, dynamic>> _addresses = [];
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
        _addresses = (res.data['data'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load addresses: $e')),
        );
      }
    }
  }

  Future<void> _deleteAddress(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Address'),
        content: const Text('Are you sure you want to delete this address?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(dioClientProvider)
          .dio
          .delete('${ApiConstants.addresses}/$id');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _setDefault(String id) async {
    try {
      await ref
          .read(dioClientProvider)
          .dio
          .put('${ApiConstants.addresses}/$id/default');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default address updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set default: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editAddress(Map<String, dynamic> address) async {
    final labelCtrl =
        TextEditingController(text: address['label'] as String? ?? '');
    final lineCtrl =
        TextEditingController(text: address['address_line'] as String? ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label (e.g. Home, Work)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lineCtrl,
              decoration: const InputDecoration(
                labelText: 'Address description',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(dioClientProvider).dio.put(
        '${ApiConstants.addresses}/${address['id']}',
        data: {
          'addressLine': lineCtrl.text.trim(),
          'label': labelCtrl.text.trim(),
        },
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving address: $e')),
        );
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
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _addresses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final a = _addresses[i];
                    final isDefault = a['is_default'] == true;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: isDefault ? Colors.orange : Colors.grey,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(
                                      a['label'] as String? ?? 'Address',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                    if (isDefault) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Default',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.orange,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(
                                    a['address_line'] as String,
                                    style: TextStyle(
                                        color: Colors.grey[600], fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            // Set as default
                            if (!isDefault)
                              IconButton(
                                icon: const Icon(Icons.star_outline,
                                    color: Colors.orange),
                                tooltip: 'Set as default',
                                onPressed: () => _setDefault(a['id'] as String),
                              ),
                            // Edit
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: Colors.blue),
                              tooltip: 'Edit',
                              onPressed: () => _editAddress(a),
                            ),
                            // Delete
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: 'Delete',
                              onPressed: () =>
                                  _deleteAddress(a['id'] as String),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
