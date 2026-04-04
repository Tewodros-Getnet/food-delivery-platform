import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await ref.read(dioClientProvider).dio.get(ApiConstants.profile);
      setState(() {
        _profile = res.data['data'] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider.notifier).logout()),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('Failed to load profile'))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Center(
                      child: CircleAvatar(
                    radius: 48,
                    backgroundImage: _profile!['profile_photo_url'] != null
                        ? NetworkImage(_profile!['profile_photo_url'] as String)
                        : null,
                    child: _profile!['profile_photo_url'] == null
                        ? const Icon(Icons.person, size: 48)
                        : null,
                  )),
                  const SizedBox(height: 16),
                  Center(
                      child: Text(
                          _profile!['display_name'] as String? ?? 'No name',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold))),
                  Center(
                      child: Text(_profile!['email'] as String? ?? '',
                          style: TextStyle(color: Colors.grey[600]))),
                  const SizedBox(height: 24),
                  ListTile(
                      leading: const Icon(Icons.location_on),
                      title: const Text('Saved Addresses'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/addresses')),
                  ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title: const Text('Order History'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/orders')),
                  ListTile(
                      leading: const Icon(Icons.lock),
                      title: const Text('Change Password'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showChangePasswordDialog(context)),
                ]),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Change Password'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: currentCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Current Password')),
                const SizedBox(height: 8),
                TextField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'New Password')),
              ]),
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
                            .put(ApiConstants.password, data: {
                          'currentPassword': currentCtrl.text,
                          'newPassword': newCtrl.text
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
                    child: const Text('Update')),
              ],
            ));
  }
}
