import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/widgets/theme_switcher.dart';

class RiderProfileScreen extends ConsumerStatefulWidget {
  const RiderProfileScreen({super.key});
  @override
  ConsumerState<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends ConsumerState<RiderProfileScreen> {
  // User profile
  Map<String, dynamic>? _profile;
  // Rider-specific info (vehicle, restaurant assignment)
  Map<String, dynamic>? _riderProfile;
  // Invitation / team info
  Map<String, dynamic>? _invitationData;

  bool _loading      = true;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      final results = await Future.wait([
        dio.get(ApiConstants.profile),
        dio.get(ApiConstants.ridersProfile).catchError((_) => null),
        dio.get(ApiConstants.ridersInvitation).catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _profile      = results[0]?.data['data']  as Map<String, dynamic>?;
        _riderProfile = results[1]?.data['data']  as Map<String, dynamic>?;
        _invitationData = results[2]?.data['data'] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Photo upload ──────────────────────────────────────────────────────────

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 800);
    if (picked == null || !mounted) return;
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
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Edit profile (name + phone) ───────────────────────────────────────────

  void _showEditProfileSheet() {
    final nameCtrl  = TextEditingController(
        text: _profile?['display_name'] as String? ?? '');
    final phoneCtrl = TextEditingController(
        text: _profile?['phone'] as String? ?? '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Edit Profile',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final name  = nameCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          if (name.isEmpty) return;
                          setS(() => saving = true);
                          try {
                            await ref.read(dioClientProvider).dio.put(
                              ApiConstants.profile,
                              data: {
                                'displayName': name,
                                if (phone.isNotEmpty) 'phone': phone,
                              },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Profile updated')),
                              );
                            }
                          } catch (e) {
                            setS(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save Changes',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Edit vehicle info ─────────────────────────────────────────────────────

  void _showVehicleSheet() {
    final vehicleTypes = ['Motorcycle', 'Bicycle', 'Car', 'Scooter', 'On Foot'];
    String? selectedType =
        _riderProfile?['vehicle_type'] as String? ?? 'Motorcycle';
    final plateCtrl = TextEditingController(
        text: _riderProfile?['vehicle_plate'] as String? ?? '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Vehicle Info',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('This helps restaurants know how your deliveries arrive',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 20),

              // Vehicle type
              DropdownButtonFormField<String>(
                value: vehicleTypes.contains(selectedType)
                    ? selectedType
                    : vehicleTypes.first,
                decoration: const InputDecoration(
                  labelText: 'Vehicle Type',
                  prefixIcon: Icon(Icons.delivery_dining_outlined, size: 20),
                  border: OutlineInputBorder(),
                ),
                items: vehicleTypes.map((t) => DropdownMenuItem(
                    value: t, child: Text(t))).toList(),
                onChanged: (v) => setS(() => selectedType = v),
              ),
              const SizedBox(height: 12),

              // Plate / identifier
              TextField(
                controller: plateCtrl,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Plate / ID Number (optional)',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20),
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 3-04567 AA',
                ),
              ),
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
                              ApiConstants.ridersProfile,
                              data: {
                                'vehicle_type': selectedType,
                                if (plateCtrl.text.trim().isNotEmpty)
                                  'vehicle_plate': plateCtrl.text.trim(),
                              },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Vehicle info saved')),
                              );
                            }
                          } catch (e) {
                            setS(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Change password ───────────────────────────────────────────────────────

  void _showChangePasswordSheet() {
    final currentCtrl  = TextEditingController();
    final newCtrl      = TextEditingController();
    bool saving        = false;
    bool obscureCurrent = true;
    bool obscureNew    = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Change Password',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: currentCtrl,
                obscureText: obscureCurrent,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrent
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setS(() => obscureCurrent = !obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: obscureNew,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'New Password (min 8 chars)',
                  prefixIcon: const Icon(Icons.lock_reset_outlined, size: 20),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setS(() => obscureNew = !obscureNew),
                  ),
                ),
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
                              const SnackBar(
                                  content: Text(
                                      'Password must be at least 8 characters'),
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
                                const SnackBar(
                                    content: Text('Password updated')),
                              );
                            }
                          } catch (e) {
                            setS(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Update Password',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Failed to load profile'),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final name     = _profile!['display_name'] as String? ?? '';
    final email    = _profile!['email']         as String? ?? '';
    final phone    = _profile!['phone']         as String?;
    final photoUrl = _profile!['profile_photo_url'] as String?;
    final rating   = _profile!['average_rating'];

    // Vehicle
    final vehicleType  = _riderProfile?['vehicle_type']  as String?;
    final vehiclePlate = _riderProfile?['vehicle_plate'] as String?;

    // Restaurant assignment (from invitation endpoint)
    final invStatus   = _invitationData?['status'] as String?;
    final restName    = _invitationData?['restaurant_name'] as String?;
    final isAssigned  = invStatus == 'accepted' && restName != null;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          // ── Hero SliverAppBar ───────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            title: const Text('Profile',
                style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout_outlined),
                tooltip: 'Sign out',
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
                      cs.primary.withValues(alpha: 0.85),
                      cs.primary,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 44),
                      // Avatar with upload button
                      GestureDetector(
                        onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                        child: Stack(
                          children: [
                            Container(
                              width: 84, height: 84,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.25),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ],
                              ),
                              child: ClipOval(
                                child: photoUrl != null
                                    ? Image.network(photoUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _defaultAvatar(cs, name))
                                    : _defaultAvatar(cs, name),
                              ),
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: cs.primary, width: 1.5),
                                ),
                                child: _uploadingPhoto
                                    ? Padding(
                                        padding: const EdgeInsets.all(5),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: cs.primary))
                                    : Icon(Icons.camera_alt,
                                        size: 14, color: cs.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Name (shows email if no name set yet)
                      Text(
                        name.isNotEmpty ? name : email,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold),
                      ),
                      if (phone != null && phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(phone,
                            style: TextStyle(
                                color: Colors.white
                                    .withValues(alpha: 0.75),
                                fontSize: 12)),
                      ],
                      if (rating != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 16),
                            const SizedBox(width: 3),
                            Text(
                              '${double.tryParse(rating.toString())?.toStringAsFixed(1) ?? rating}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Restaurant assignment card ──────────────────────────
                  if (isAssigned) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withValues(alpha: 0.15),
                            cs.primary.withValues(alpha: 0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: cs.primary.withValues(alpha: 0.35),
                            width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.storefront_rounded,
                                color: cs.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ACTIVE TEAM',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  restName!,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'You are assigned to this restaurant',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurface.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.green, size: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Personal info ─────────────────────────────────────
                  _SectionHeader('Personal Info'),
                  const SizedBox(height: 8),
                  _SettingsCard(children: [
                    _SettingsTile(
                      icon: Icons.edit_outlined,
                      iconColor: Colors.blue,
                      title: 'Edit Profile',
                      subtitle: [
                        if (name.isNotEmpty) name,
                        if (phone != null && phone.isNotEmpty) phone!,
                        if (name.isEmpty && (phone == null || phone.isEmpty))
                          'Name · Phone number',
                      ].join(' · '),
                      onTap: _showEditProfileSheet,
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // ── Vehicle ───────────────────────────────────────────
                  _SectionHeader('Vehicle'),
                  const SizedBox(height: 8),
                  _SettingsCard(children: [
                    _SettingsTile(
                      icon: Icons.delivery_dining_outlined,
                      iconColor: Colors.orange,
                      title: vehicleType ?? 'Set vehicle type',
                      subtitle: vehiclePlate != null && vehiclePlate.isNotEmpty
                          ? 'Plate: $vehiclePlate'
                          : 'Motorcycle · Bicycle · Car · Scooter',
                      onTap: _showVehicleSheet,
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // ── Account ───────────────────────────────────────────
                  _SectionHeader('Account'),
                  const SizedBox(height: 8),
                  _SettingsCard(children: [
                    _SettingsTile(
                      icon: Icons.lock_outline,
                      iconColor: Colors.purple,
                      title: 'Change Password',
                      onTap: _showChangePasswordSheet,
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // ── Preferences ───────────────────────────────────────
                  _SectionHeader('Preferences'),
                  const SizedBox(height: 8),
                  _SettingsCard(children: [
                    const ThemeSwitcherTile(),
                  ]),

                  const SizedBox(height: 28),

                  // ── Sign out ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmSignOut(context),
                      icon: const Icon(Icons.logout_outlined,
                          color: Colors.red),
                      label: const Text('Sign Out',
                          style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
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

  Widget _defaultAvatar(ColorScheme cs, String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: Colors.white.withValues(alpha: 0.2),
      child: Center(
        child: Text(initial,
            style: const TextStyle(
                fontSize: 32, color: Colors.white,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 0),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.45),
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                cs.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right,
                  color: cs.onSurface.withValues(alpha: 0.3), size: 20),
          ]),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Divider(
      height: 1,
      indent: 66,
      endIndent: 0,
      color: Theme.of(context)
          .dividerColor
          .withValues(alpha: 0.5));
}
