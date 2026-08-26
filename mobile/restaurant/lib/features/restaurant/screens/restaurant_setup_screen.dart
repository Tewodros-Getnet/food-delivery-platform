import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import '../../../features/auth/providers/auth_provider.dart';
import 'map_picker_screen.dart';

class RestaurantSetupScreen extends ConsumerStatefulWidget {
  const RestaurantSetupScreen({super.key});
  @override
  ConsumerState<RestaurantSetupScreen> createState() =>
      _RestaurantSetupScreenState();
}

class _RestaurantSetupScreenState extends ConsumerState<RestaurantSetupScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _addressCtrl = TextEditingController();
  double? _latitude;
  double? _longitude;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const RestaurantMapPickerScreen()),
    );
    if (result != null) {
      setState(() {
        _latitude  = result['latitude']  as double;
        _longitude = result['longitude'] as double;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_latitude == null) {
      setState(() => _error = 'Please pin your restaurant location on the map');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final dio = ref.read(dioClientProvider).dio;

      // Save phone number to the owner's user profile first so the admin
      // can use it for contact and it appears in the restaurant drawer.
      final phone = _phoneCtrl.text.trim();
      if (phone.isNotEmpty) {
        await dio.put(
          ApiConstants.profile,
          data: {'phone': phone},
        );
      }

      // Create the restaurant profile
      await dio.post(
        ApiConstants.restaurants,
        data: {
          'name':        _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'address':     _addressCtrl.text.trim(),
          'latitude':    _latitude,
          'longitude':   _longitude,
        },
      );

      if (mounted) {
        ref.read(authProvider.notifier).onRestaurantCreated();
        context.go('/pending-approval');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRejection =
        ref.watch(authProvider).restaurantStatus == 'rejected';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero SliverAppBar ───────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary.withValues(alpha: 0.9),
                      cs.primary,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2),
                        ),
                        child: Icon(
                          isRejection
                              ? Icons.refresh_rounded
                              : Icons.add_business_rounded,
                          size: 30,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isRejection
                            ? 'Re-submit Application'
                            : 'Register Restaurant',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isRejection
                            ? 'Update your details and re-apply'
                            : 'Start accepting orders on our platform',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Form ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Info / rejection banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isRejection
                            ? cs.errorContainer
                            : cs.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isRejection
                              ? cs.error.withValues(alpha: 0.3)
                              : cs.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isRejection
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline_rounded,
                            size: 16,
                            color: isRejection
                                ? cs.onErrorContainer
                                : cs.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isRejection
                                  ? 'Your previous application was rejected. '
                                      'Please review and update your details before re-submitting.'
                                  : 'Your restaurant will be reviewed by our team before going live. '
                                      'Approval usually takes 1–2 business days.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: isRejection
                                    ? cs.onErrorContainer
                                    : cs.primary.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Restaurant name
                    _Label('Restaurant Name'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _dec(context,
                          hint: 'e.g. Bella Vista Kitchen',
                          icon: Icons.storefront_outlined),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),

                    const SizedBox(height: 20),

                    // Contact phone — riders call this number for pickups,
                    // customers can also see it on the restaurant detail page.
                    _Label('Contact Phone Number'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9+\-\s()]')),
                      ],
                      decoration: _dec(context,
                          hint: 'e.g. +251 91 234 5678',
                          icon: Icons.phone_outlined),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final digits =
                            v.replaceAll(RegExp(r'\D'), '');
                        if (digits.length < 7) {
                          return 'Enter a valid phone number';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    // Description
                    _Label('Description (optional)'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _dec(context,
                          hint:
                              'e.g. Authentic Ethiopian cuisine with a modern twist...',
                          icon: Icons.description_outlined),
                    ),

                    const SizedBox(height: 20),

                    // Address
                    _Label('Address / Area'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _addressCtrl,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration: _dec(context,
                          hint: 'e.g. Bole, Addis Ababa',
                          icon: Icons.location_city_outlined),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),

                    const SizedBox(height: 20),

                    // Map location picker
                    _Label('Pin Location on Map'),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _pickLocation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _latitude != null
                              ? cs.primaryContainer.withValues(alpha: 0.35)
                              : cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _latitude != null
                                ? cs.primary.withValues(alpha: 0.4)
                                : cs.outline.withValues(alpha: 0.25),
                            width: _latitude != null ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _latitude != null
                                  ? cs.primary.withValues(alpha: 0.1)
                                  : cs.onSurface.withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _latitude != null
                                  ? Icons.location_on_rounded
                                  : Icons.add_location_alt_outlined,
                              size: 20,
                              color: _latitude != null
                                  ? cs.primary
                                  : cs.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _latitude != null
                                      ? 'Location selected ✓'
                                      : 'Tap to drop a pin on the map',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: _latitude != null
                                        ? cs.primary
                                        : cs.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _latitude != null
                                      ? '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                                      : 'Required — customers use this to find you',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.45),
                                    fontFamily:
                                        _latitude != null ? 'monospace' : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: cs.onSurface.withValues(alpha: 0.3)),
                        ]),
                      ),
                    ),

                    // Error messages
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 16, color: cs.onErrorContainer),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                    color: cs.onErrorContainer,
                                    fontSize: 13,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Submit button
                    FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : Text(
                              isRejection
                                  ? 'Re-submit Application'
                                  : 'Submit for Approval',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: cs.onSurface.withValues(alpha: 0.7),
        letterSpacing: 0.2,
      ),
    );
  }
}

InputDecoration _dec(
  BuildContext context, {
  required String hint,
  required IconData icon,
}) {
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
        fontSize: 14, color: cs.onSurface.withValues(alpha: 0.35)),
    prefixIcon:
        Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: 0.45)),
    filled: true,
    fillColor: cs.surfaceContainerLowest,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.primary, width: 1.8),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.error, width: 1.8),
    ),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
