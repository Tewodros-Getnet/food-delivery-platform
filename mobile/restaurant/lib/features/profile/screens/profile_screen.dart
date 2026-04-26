import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import '../../auth/providers/auth_provider.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

class RestaurantProfileScreen extends ConsumerStatefulWidget {
  const RestaurantProfileScreen({super.key});
  @override
  ConsumerState<RestaurantProfileScreen> createState() =>
      _RestaurantProfileScreenState();
}

class _RestaurantProfileScreenState
    extends ConsumerState<RestaurantProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _uploadingPhoto = false;

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

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 800,
    );
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final base64Image = base64Encode(bytes);

      await ref.read(dioClientProvider).dio.put(
        ApiConstants.profile,
        data: {'photoBase64': base64Image},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('Failed to load profile'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 52,
                            backgroundImage: _profile!['profile_photo_url'] !=
                                    null
                                ? NetworkImage(
                                    _profile!['profile_photo_url'] as String)
                                : null,
                            child: _profile!['profile_photo_url'] == null
                                ? const Icon(Icons.person, size: 52)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap:
                                  _uploadingPhoto ? null : _pickAndUploadPhoto,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E7D32),
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: _uploadingPhoto
                                    ? const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.camera_alt,
                                        color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        _profile!['display_name'] as String? ?? 'No name',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Center(
                      child: Text(
                        _profile!['email'] as String? ?? '',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ListTile(
                      leading: const Icon(Icons.bar_chart),
                      title: const Text('Analytics'),
                      subtitle: const Text('Orders, revenue and top items'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/analytics'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.access_time),
                      title: const Text('Operating Hours'),
                      subtitle:
                          const Text('Set your weekly open/close schedule'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/hours'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock),
                      title: const Text('Change Password'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showChangePasswordDialog(context),
                    ),
                  ],
                ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current Password'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(dioClientProvider).dio.put(
                  ApiConstants.password,
                  data: {
                    'currentPassword': currentCtrl.text,
                    'newPassword': newCtrl.text,
                  },
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}
