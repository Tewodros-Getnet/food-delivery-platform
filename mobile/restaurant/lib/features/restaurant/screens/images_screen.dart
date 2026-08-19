import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

class RestaurantImagesScreen extends ConsumerStatefulWidget {
  const RestaurantImagesScreen({super.key});
  @override
  ConsumerState<RestaurantImagesScreen> createState() =>
      _RestaurantImagesScreenState();
}

class _RestaurantImagesScreenState
    extends ConsumerState<RestaurantImagesScreen> {
  static const _brandColor = Color(0xFF2E7D32);

  String? _currentCoverUrl;
  String? _currentLogoUrl;
  bool _loadingCurrent = true;

  bool _uploadingCover = false;
  bool _uploadingLogo = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    try {
      final res = await ref
          .read(dioClientProvider)
          .dio
          .get(ApiConstants.myRestaurant);
      final data = res.data['data'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _currentCoverUrl = data['cover_image_url'] as String?;
          _currentLogoUrl = data['logo_url'] as String?;
          _loadingCurrent = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCurrent = false);
    }
  }

  Future<void> _pickAndUpload({required bool isCover}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: isCover ? 75 : 85,
      maxWidth: isCover ? 1200 : 600,
    );
    if (picked == null) return;

    if (isCover) {
      setState(() => _uploadingCover = true);
    } else {
      setState(() => _uploadingLogo = true);
    }

    try {
      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);

      await ref.read(dioClientProvider).dio.put(
        ApiConstants.myRestaurantImages,
        data: isCover ? {'coverBase64': b64} : {'logoBase64': b64},
      );

      await _loadCurrent();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                isCover ? 'Cover photo updated!' : 'Logo updated!'),
            backgroundColor: _brandColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingCover = false;
          _uploadingLogo = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant Images'),
      ),
      body: _loadingCurrent
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Cover photo ──────────────────────────────────────────
                _SectionLabel(
                  icon: Icons.panorama_outlined,
                  title: 'Cover Photo',
                  subtitle:
                      'Wide banner shown at the top of your listing card. '
                      'Best size: 1200 × 400 px.',
                ),
                const SizedBox(height: 12),
                _ImagePicker(
                  currentUrl: _currentCoverUrl,
                  uploading: _uploadingCover,
                  aspectRatio: 3 / 1,
                  placeholder: const Icon(Icons.panorama,
                      size: 48, color: Colors.white54),
                  onPick: () => _pickAndUpload(isCover: true),
                ),

                const SizedBox(height: 32),

                // ── Logo ─────────────────────────────────────────────────
                _SectionLabel(
                  icon: Icons.storefront_outlined,
                  title: 'Logo',
                  subtitle:
                      'Square icon shown on your restaurant card and detail page. '
                      'Best size: 400 × 400 px.',
                ),
                const SizedBox(height: 12),
                Center(
                  child: _ImagePicker(
                    currentUrl: _currentLogoUrl,
                    uploading: _uploadingLogo,
                    aspectRatio: 1,
                    width: 160,
                    borderRadius: 80,
                    placeholder: const Icon(Icons.storefront,
                        size: 40, color: Colors.white54),
                    onPick: () => _pickAndUpload(isCover: false),
                  ),
                ),

                const SizedBox(height: 32),

                // Tip
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline,
                          color: _brandColor, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'High-quality photos significantly increase customer '
                          'clicks. Use well-lit images that show your food or '
                          'restaurant interior.',
                          style: TextStyle(
                              fontSize: 13, color: _brandColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionLabel(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16, color: Color(0xFF2E7D32)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Reusable image picker tile ────────────────────────────────────────────────

class _ImagePicker extends StatelessWidget {
  final String? currentUrl;
  final bool uploading;
  final double aspectRatio;
  final double? width;
  final double borderRadius;
  final Widget placeholder;
  final VoidCallback onPick;

  const _ImagePicker({
    required this.currentUrl,
    required this.uploading,
    required this.aspectRatio,
    required this.placeholder,
    required this.onPick,
    this.width,
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final content = AspectRatio(
      aspectRatio: aspectRatio,
      child: currentUrl != null
          ? CachedNetworkImage(
              imageUrl: currentUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: Colors.grey[200]),
              errorWidget: (_, __, ___) => _emptyState(),
            )
          : _emptyState(),
    );

    return GestureDetector(
      onTap: uploading ? null : onPick,
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            children: [
              content,
              // Dark overlay + camera icon
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black
                        .withValues(alpha: uploading ? 0.55 : 0.28),
                  ),
                  alignment: Alignment.center,
                  child: uploading
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.camera_alt,
                                color: Colors.white, size: 28),
                            const SizedBox(height: 6),
                            Text(
                              currentUrl != null
                                  ? 'Tap to change'
                                  : 'Tap to upload',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Container(
        color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
        child: Center(child: placeholder),
      );
}
