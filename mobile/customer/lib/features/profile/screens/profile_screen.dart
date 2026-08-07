import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/widgets/language_switcher.dart';
import '../../../l10n/app_localizations.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
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
      await ref.read(dioClientProvider).dio.put(
        ApiConstants.profile,
        data: {'photoBase64': base64Encode(bytes)},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).profilePhotoUpdated),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).photoUploadFailed),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profile == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context).failedToLoadProfile),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _load,
                child: Text(AppLocalizations.of(context).retry)),
          ]),
        ),
      );
    }

    final name = _profile!['display_name'] as String? ?? 'No name';
    final email = _profile!['email'] as String? ?? '';
    final phone = _profile!['phone'] as String?;
    final photoUrl = _profile!['profile_photo_url'] as String?;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // ── Hero header ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            title: Text(AppLocalizations.of(context).myProfile,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout_outlined),
                tooltip: AppLocalizations.of(context).signOut,
                onPressed: () => _confirmSignOut(context),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.orange.shade600,
                      Colors.deepOrange.shade400,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      // Avatar
                      GestureDetector(
                        onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                        child: Stack(
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3))
                                ],
                              ),
                              child: ClipOval(
                                child: photoUrl != null
                                    ? Image.network(photoUrl, fit: BoxFit.cover)
                                    : Container(
                                        color: Colors.orange.shade200,
                                        child: Center(
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                                fontSize: 36,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.orange, width: 1.5),
                                ),
                                child: _uploadingPhoto
                                    ? const Padding(
                                        padding: EdgeInsets.all(5),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.orange),
                                      )
                                    : const Icon(Icons.camera_alt,
                                        size: 14, color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(email,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Quick stats row ──────────────────────────────────────
                  Row(children: [
                    _StatChip(
                        icon: Icons.receipt_long,
                        label: AppLocalizations.of(context).orders,
                        onTap: () => context.push('/orders')),
                    const SizedBox(width: 10),
                    _StatChip(
                        icon: Icons.favorite,
                        label: AppLocalizations.of(context).saved,
                        color: Colors.red,
                        onTap: () => context.push('/favorites')),
                    const SizedBox(width: 10),
                    _StatChip(
                        icon: Icons.location_on,
                        label: AppLocalizations.of(context).addresses,
                        color: Colors.blue,
                        onTap: () => context.push('/addresses')),
                  ]),

                  const SizedBox(height: 24),

                  // ── Account section ──────────────────────────────────────
                  _SectionLabel(AppLocalizations.of(context).account),
                  _MenuCard(children: [
                    _MenuItem(
                      icon: Icons.person_outline,
                      iconColor: Colors.orange,
                      title: AppLocalizations.of(context).editProfile,
                      subtitle: name,
                      onTap: () => _showEditProfileDialog(context),
                    ),
                    _MenuDivider(),
                    _MenuItem(
                      icon: Icons.phone_outlined,
                      iconColor: Colors.green,
                      title: AppLocalizations.of(context).phoneNumber,
                      subtitle: phone?.isNotEmpty == true
                          ? phone!
                          : AppLocalizations.of(context).notSet,
                      onTap: () => _showEditProfileDialog(context),
                    ),
                    _MenuDivider(),
                    _MenuItem(
                      icon: Icons.lock_outline,
                      iconColor: Colors.purple,
                      title: AppLocalizations.of(context).changePassword,
                      onTap: () => _showChangePasswordDialog(context),
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // ── My Activity section ──────────────────────────────────
                  _SectionLabel(AppLocalizations.of(context).myActivity),
                  _MenuCard(children: [
                    _MenuItem(
                      icon: Icons.receipt_long_outlined,
                      iconColor: Colors.blue,
                      title: AppLocalizations.of(context).orderHistory,
                      subtitle: AppLocalizations.of(context).viewAllPastOrders,
                      onTap: () => context.push('/orders'),
                    ),
                    _MenuDivider(),
                    _MenuItem(
                      icon: Icons.favorite_border,
                      iconColor: Colors.red,
                      title: AppLocalizations.of(context).savedRestaurants,
                      subtitle: AppLocalizations.of(context).yourFavouritePlaces,
                      onTap: () => context.push('/favorites'),
                    ),
                    _MenuDivider(),
                    _MenuItem(
                      icon: Icons.location_on_outlined,
                      iconColor: Colors.teal,
                      title: AppLocalizations.of(context).addresses,
                      subtitle: AppLocalizations.of(context).manageDeliveryLocations,
                      onTap: () => context.push('/addresses'),
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // ── Offers & Rewards section (placeholder for future) ────
                  _SectionLabel(AppLocalizations.of(context).offersAndRewards),
                  _MenuCard(children: [
                    _MenuItem(
                      icon: Icons.local_offer_outlined,
                      iconColor: Colors.orange,
                      title: AppLocalizations.of(context).vouchersAndPromoCodes,
                      subtitle: AppLocalizations.of(context).comingSoon,
                      trailing: _ComingSoonBadge(),
                      onTap: null,
                    ),
                    _MenuDivider(),
                    _MenuItem(
                      icon: Icons.stars_outlined,
                      iconColor: Colors.amber,
                      title: AppLocalizations.of(context).loyaltyPoints,
                      subtitle: AppLocalizations.of(context).comingSoon,
                      trailing: _ComingSoonBadge(),
                      onTap: null,
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // ── Language section ─────────────────────────────────────
                  _SectionLabel(AppLocalizations.of(context).language),
                  _MenuCard(children: [
                    const LanguageSwitcherTile(),
                  ]),

                  const SizedBox(height: 20),

                  // ── Support section ──────────────────────────────────────
                  _SectionLabel(AppLocalizations.of(context).support),
                  _MenuCard(children: [
                    _MenuItem(
                      icon: Icons.help_outline,
                      iconColor: Colors.indigo,
                      title: AppLocalizations.of(context).helpCenter,
                      subtitle: AppLocalizations.of(context).faqsAndSupport,
                      trailing: _ComingSoonBadge(),
                      onTap: null,
                    ),
                    _MenuDivider(),
                    _MenuItem(
                      icon: Icons.flag_outlined,
                      iconColor: Colors.red,
                      title: AppLocalizations.of(context).reportProblemTitle,
                      onTap: () => context.push('/orders'),
                    ),
                    _MenuDivider(),
                    _MenuItem(
                      icon: Icons.info_outline,
                      iconColor: Colors.grey,
                      title: AppLocalizations.of(context).about,
                      subtitle: AppLocalizations.of(context).appVersion,
                      onTap: null,
                    ),
                  ]),

                  const SizedBox(height: 28),

                  // ── Sign out button ──────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmSignOut(context),
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: Text(AppLocalizations.of(context).signOut,
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.red.shade200),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
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

  void _confirmSignOut(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.signOut),
        content: Text(l10n.signOutConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.signOut,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    final nameCtrl =
        TextEditingController(text: _profile?['display_name'] as String? ?? '');
    final phoneCtrl =
        TextEditingController(text: _profile?['phone'] as String? ?? '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(AppLocalizations.of(ctx).editProfile,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _field(nameCtrl, AppLocalizations.of(ctx).displayName, Icons.person_outline),
              const SizedBox(height: 12),
              _field(phoneCtrl, AppLocalizations.of(ctx).phoneNumber, Icons.phone_outlined,
                  keyboard: TextInputType.phone),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setS(() => saving = true);
                          try {
                            await ref.read(dioClientProvider).dio.put(
                              ApiConstants.profile,
                              data: {
                                if (nameCtrl.text.trim().isNotEmpty)
                                  'displayName': nameCtrl.text.trim(),
                                if (phoneCtrl.text.trim().isNotEmpty)
                                  'phone': phoneCtrl.text.trim(),
                              },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(AppLocalizations.of(context).profileUpdated),
                                    backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            setS(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('${AppLocalizations.of(context).error}: $e'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(AppLocalizations.of(ctx).saveChanges,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool saving = false;
    bool obscureCurrent = true;
    bool obscureNew = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(AppLocalizations.of(ctx).changePassword,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: currentCtrl,
                obscureText: obscureCurrent,
                decoration: _inputDecoration(
                    AppLocalizations.of(ctx).currentPassword, Icons.lock_outline,
                    suffix: IconButton(
                      icon: Icon(obscureCurrent
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setS(() => obscureCurrent = !obscureCurrent),
                    )),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: obscureNew,
                decoration: _inputDecoration(
                    AppLocalizations.of(ctx).newPasswordHint, Icons.lock_reset_outlined,
                    suffix: IconButton(
                      icon: Icon(obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setS(() => obscureNew = !obscureNew),
                    )),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (newCtrl.text.length < 8) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(AppLocalizations.of(context).passwordTooShort),
                                  backgroundColor: Colors.red),
                            );
                            return;
                          }
                          setS(() => saving = true);
                          try {
                            await ref.read(dioClientProvider).dio.put(
                              ApiConstants.password,
                              data: {
                                'currentPassword': currentCtrl.text,
                                'newPassword': newCtrl.text,
                              },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(AppLocalizations.of(context).passwordUpdated),
                                    backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            setS(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Failed: $e'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(AppLocalizations.of(ctx).updatePassword,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      textCapitalization:
          keyboard == null ? TextCapitalization.words : TextCapitalization.none,
      decoration: _inputDecoration(label, icon),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon,
      {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.orange, width: 1.5),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
        height: 1, indent: 56, endIndent: 0, color: Colors.grey[100]);
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            // Icon container
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: onTap != null
                              ? Colors.black87
                              : Colors.grey[400])),
                  if (subtitle != null)
                    Text(subtitle!,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            // Trailing
            trailing ??
                (onTap != null
                    ? Icon(Icons.chevron_right,
                        color: Colors.grey[400], size: 20)
                    : const SizedBox.shrink()),
          ]),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _StatChip({
    required this.icon,
    required this.label,
    this.color = Colors.orange,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
          ]),
        ),
      ),
    );
  }
}

class _ComingSoonBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text(AppLocalizations.of(context).comingSoon,
          style: TextStyle(
              fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600)),
    );
  }
}
