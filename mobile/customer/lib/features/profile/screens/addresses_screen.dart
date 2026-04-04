import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

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

  void _showAddDialog() {
    final lineCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lonCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Add Address'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: labelCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Label (e.g. Home)')),
                const SizedBox(height: 8),
                TextField(
                    controller: lineCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Address Line')),
                const SizedBox(height: 8),
                TextField(
                    controller: latCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Latitude')),
                const SizedBox(height: 8),
                TextField(
                    controller: lonCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Longitude')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(dioClientProvider)
                            .dio
                            .post(ApiConstants.addresses, data: {
                          'addressLine': lineCtrl.text,
                          'latitude': double.parse(latCtrl.text),
                          'longitude': double.parse(lonCtrl.text),
                          'label': labelCtrl.text,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _load();
                      } catch (e) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
                    child: const Text('Add')),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Addresses')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _addresses.isEmpty
              ? const Center(child: Text('No saved addresses'))
              : ListView.builder(
                  itemCount: _addresses.length,
                  itemBuilder: (ctx, i) {
                    final a = _addresses[i] as Map<String, dynamic>;
                    return ListTile(
                      leading:
                          const Icon(Icons.location_on, color: Colors.orange),
                      title: Text(a['label'] as String? ?? 'Address'),
                      subtitle: Text(a['address_line'] as String),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (a['is_default'] == true)
                          const Chip(
                              label: Text('Default',
                                  style: TextStyle(fontSize: 11))),
                        IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteAddress(a['id'] as String)),
                      ]),
                    );
                  },
                ),
    );
  }
}
