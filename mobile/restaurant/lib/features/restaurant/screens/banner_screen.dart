import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

class PromoBannerScreen extends ConsumerStatefulWidget {
  const PromoBannerScreen({super.key});

  @override
  ConsumerState<PromoBannerScreen> createState() => _PromoBannerScreenState();
}

class _PromoBannerScreenState extends ConsumerState<PromoBannerScreen> {
  final _textCtrl = TextEditingController();
  String? _existingImageUrl;
  File? _newImage;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ref
          .read(dioClientProvider)
          .dio
          .get(ApiConstants.myRestaurant);
      final data = res.data['data'] as Map<String, dynamic>?;
      setState(() {
        _textCtrl.text = data?['promo_banner_text'] as String? ?? '';
        _existingImageUrl =
            data?['promo_banner_image_url'] as String?;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
      maxHeight: 400,
    );
    if (picked != null) setState(() => _newImage = File(picked.path));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String? imageBase64;
      if (_newImage != null) {
        final bytes = await _newImage!.readAsBytes();
        imageBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      await ref.read(dioClientProvider).dio.put(
        ApiConstants.myRestaurantBanner,
        data: {
          'text': _textCtrl.text.trim().isEmpty
              ? null
              : _textCtrl.text.trim(),
          if (imageBase64 != null) 'imageBase64': imageBase64,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Banner saved!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Banner?'),
        content: const Text(
            'This will remove the promotional banner from your listing.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(dioClientProvider).dio.put(
        ApiConstants.myRestaurantBanner,
        data: {'text': null},
      );
      setState(() {
        _textCtrl.clear();
        _existingImageUrl = null;
        _newImage = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Banner cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = _textCtrl.text.isNotEmpty ||
        _existingImageUrl != null ||
        _newImage != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotional Banner'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          if (hasContent)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear banner',
              onPressed: _saving ? null : _clear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The banner appears at the top of your restaurant listing. Use it for promotions, discounts, or announcements.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Preview
                if (_newImage != null || _existingImageUrl != null) ...[
                  const Text('Preview',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        _newImage != null
                            ? Image.file(
                                _newImage!,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : CachedNetworkImage(
                                imageUrl: _existingImageUrl!,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                        if (_textCtrl.text.isNotEmpty)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              color: Colors.black54,
                              child: Text(
                                _textCtrl.text,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Banner text
                const Text('Banner Text',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _textCtrl,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. "Free delivery today!" or "20% off all orders"',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_textCtrl.text.length}/120 characters',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black38),
                ),
                const SizedBox(height: 20),

                // Banner image
                const Text('Banner Image (optional)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    _newImage != null
                        ? 'Image selected ✓'
                        : _existingImageUrl != null
                            ? 'Change image'
                            : 'Pick banner image',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                  ),
                ),
                const SizedBox(height: 32),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Save Banner',
                            style: TextStyle(
                                color: Colors.white, fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
