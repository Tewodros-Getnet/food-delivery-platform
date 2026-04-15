import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

class MyRidersScreen extends ConsumerStatefulWidget {
  const MyRidersScreen({super.key});
  @override
  ConsumerState<MyRidersScreen> createState() => _MyRidersScreenState();
}

class _MyRidersScreenState extends ConsumerState<MyRidersScreen> {
  List<Map<String, dynamic>> _riders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(dioClientProvider)
          .dio
          .get(ApiConstants.myRestaurantRiders);
      setState(() {
        _riders = (res.data['data'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _invite() async {
    final emailCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite Rider'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Rider email address',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Invite'),
          ),
        ],
      ),
    );
    if (confirmed != true || emailCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(dioClientProvider).dio.post(
        ApiConstants.myRestaurantRidersInvite,
        data: {'email': emailCtrl.text.trim()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation sent successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _remove(String riderId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Rider'),
        content: Text('Remove $name from your team?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(dioClientProvider).dio.delete(
            '${ApiConstants.myRestaurantRiders}/$riderId',
          );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Riders'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Invite Rider',
            onPressed: _invite,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('Error: $_error',
                      style: const TextStyle(color: Colors.red)))
              : _riders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.delivery_dining,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('No riders yet',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 16)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _invite,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Invite a Rider'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32)),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _riders.length,
                        itemBuilder: (ctx, i) {
                          final r = _riders[i];
                          final availability =
                              r['availability'] as String? ?? 'offline';
                          final availColor = availability == 'available'
                              ? Colors.green
                              : availability == 'on_delivery'
                                  ? Colors.orange
                                  : Colors.grey;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.green.shade50,
                                child: const Icon(Icons.delivery_dining,
                                    color: Color(0xFF2E7D32)),
                              ),
                              title: Text(
                                r['display_name'] as String? ??
                                    r['email'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r['email'] as String,
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12)),
                                  Row(children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                          color: availColor,
                                          shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(availability.replaceAll('_', ' '),
                                        style: TextStyle(
                                            color: availColor, fontSize: 12)),
                                  ]),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Colors.red),
                                onPressed: () => _remove(
                                  r['id'] as String,
                                  r['display_name'] as String? ??
                                      r['email'] as String,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
