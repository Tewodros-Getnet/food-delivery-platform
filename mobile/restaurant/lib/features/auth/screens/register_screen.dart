import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';
import '../../restaurant/screens/map_picker_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // Step controllers
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();

  // Step 1 — Account
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure       = true;

  // Step 2 — Restaurant info
  final _nameCtrl    = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _addressCtrl = TextEditingController();
  double? _latitude;
  double? _longitude;
  String? _mapError;

  int _step = 0; // 0 = account, 1 = restaurant info
  late final AnimationController _anim;
  late final Animation<Offset> _slideIn;

  static const _totalSteps = 2;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slideIn = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _goToStep(int next) {
    setState(() => _step = next);
    _anim.forward(from: 0);
  }

  bool _validateStep1() => _step1Key.currentState!.validate();

  bool _validateStep2() {
    final formOk = _step2Key.currentState!.validate();
    if (_latitude == null) {
      setState(() => _mapError = 'Please pick your restaurant location on the map');
      return false;
    }
    setState(() => _mapError = null);
    return formOk;
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
        _mapError  = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_validateStep2()) return;
    // Register creates the user account only; restaurant profile is created
    // by RestaurantSetupScreen after OTP verification.
    // We store the restaurant fields in local state to hand off to /setup.
    await ref.read(authProvider.notifier).register(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final cs   = Theme.of(context).colorScheme;
    final tt   = Theme.of(context).textTheme;

    ref.listen(authProvider, (_, next) {
      if (next.status == AuthStatus.pendingVerification) {
        context.go('/verify-otp');
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          // Gradient background
          Positioned(
            top: 0, left: 0, right: 0,
            height: MediaQuery.of(context).size.height * 0.30,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary.withValues(alpha: 0.9), cs.primary],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── Top bar ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () {
                          if (_step == 0) {
                            context.pop();
                          } else {
                            _goToStep(_step - 1);
                          }
                        },
                      ),
                      const Spacer(),
                      // Step indicator pills
                      Row(
                        children: List.generate(_totalSteps, (i) {
                          final active = i == _step;
                          final done   = i < _step;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: active || done
                                  ? Colors.white
                                  : Colors.white38,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),

                // Hero icon + title
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Column(
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          _step == 0
                              ? Icons.person_add_alt_1_rounded
                              : Icons.storefront_rounded,
                          size: 32, color: cs.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Column(
                          key: ValueKey(_step),
                          children: [
                            Text(
                              _step == 0
                                  ? 'Create your account'
                                  : 'Register your restaurant',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _step == 0
                                  ? 'Step 1 of 2 — Account credentials'
                                  : 'Step 2 of 2 — Restaurant details',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── White card ─────────────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 20,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SlideTransition(
                      position: _slideIn,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _step == 0
                              ? _Step1(
                                  key: const ValueKey(0),
                                  formKey: _step1Key,
                                  emailCtrl: _emailCtrl,
                                  passwordCtrl: _passwordCtrl,
                                  obscure: _obscure,
                                  onToggleObscure: () =>
                                      setState(() => _obscure = !_obscure),
                                  error: auth.error,
                                  isLoading: auth.isLoading,
                                  onNext: () {
                                    if (_validateStep1()) _goToStep(1);
                                  },
                                  onSignIn: () => context.pop(),
                                )
                              : _Step2(
                                  key: const ValueKey(1),
                                  formKey: _step2Key,
                                  nameCtrl: _nameCtrl,
                                  descCtrl: _descCtrl,
                                  addressCtrl: _addressCtrl,
                                  latitude: _latitude,
                                  longitude: _longitude,
                                  mapError: _mapError,
                                  onPickLocation: _pickLocation,
                                  error: auth.error,
                                  isLoading: auth.isLoading,
                                  onSubmit: _submit,
                                ),
                        ),
                      ),
                    ),
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

// ── Step 1 — Account credentials ─────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final String? error;
  final bool isLoading;
  final VoidCallback onNext;
  final VoidCallback onSignIn;

  const _Step1({
    super.key,
    required this.formKey,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.error,
    required this.isLoading,
    required this.onNext,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Account details',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('This is how you\'ll sign in to the portal',
              style: tt.bodySmall
                  ?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 24),

          TextFormField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: authInputDec(context,
                label: 'Work email address',
                icon: Icons.email_outlined),
            validator: (v) =>
                v != null && v.contains('@') ? null : 'Enter a valid email',
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: passwordCtrl,
            obscureText: obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onNext(),
            decoration: authInputDec(
              context,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
                onPressed: onToggleObscure,
              ),
            ),
            validator: (v) =>
                v != null && v.length >= 8 ? null : 'Min 8 characters',
          ),

          // Password strength hint
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Use at least 8 characters. Mixing letters, numbers and symbols is stronger.',
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.4),
                  height: 1.4),
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 14),
            AuthErrorBanner(message: error!),
          ],

          const SizedBox(height: 28),

          FilledButton(
            onPressed: isLoading ? null : onNext,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Continue',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Already have an account? ',
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 14)),
              GestureDetector(
                onTap: onSignIn,
                child: Text('Sign in',
                    style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Step 2 — Restaurant info ──────────────────────────────────────────────────

class _Step2 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController addressCtrl;
  final double? latitude;
  final double? longitude;
  final String? mapError;
  final VoidCallback onPickLocation;
  final String? error;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _Step2({
    super.key,
    required this.formKey,
    required this.nameCtrl,
    required this.descCtrl,
    required this.addressCtrl,
    required this.latitude,
    required this.longitude,
    required this.mapError,
    required this.onPickLocation,
    required this.error,
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasLocation = latitude != null;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Restaurant details',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('This info will be shown to customers',
              style: tt.bodySmall
                  ?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 24),

          // Restaurant name
          TextFormField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: authInputDec(context,
                label: 'Restaurant name',
                icon: Icons.storefront_outlined),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          // Description
          TextFormField(
            controller: descCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: authInputDec(context,
                label: 'Description (optional)',
                icon: Icons.description_outlined),
          ),
          const SizedBox(height: 16),

          // Address
          TextFormField(
            controller: addressCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: authInputDec(context,
                label: 'Area / street address',
                icon: Icons.location_city_outlined),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          // Map picker
          GestureDetector(
            onTap: onPickLocation,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: hasLocation
                    ? cs.primaryContainer.withValues(alpha: 0.4)
                    : cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: mapError != null
                      ? cs.error
                      : hasLocation
                          ? cs.primary.withValues(alpha: 0.5)
                          : cs.outline.withValues(alpha: 0.25),
                  width: hasLocation ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: hasLocation
                          ? cs.primary.withValues(alpha: 0.12)
                          : cs.onSurface.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      hasLocation
                          ? Icons.location_on_rounded
                          : Icons.add_location_alt_outlined,
                      size: 20,
                      color: hasLocation
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
                          hasLocation
                              ? 'Location selected ✓'
                              : 'Pin location on map',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: hasLocation
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasLocation
                              ? '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}'
                              : 'Tap to open the map and drop a pin',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.45),
                            fontFamily: hasLocation ? 'monospace' : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: cs.onSurface.withValues(alpha: 0.3)),
                ],
              ),
            ),
          ),

          if (mapError != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(mapError!,
                  style: TextStyle(color: cs.error, fontSize: 12)),
            ),
          ],

          if (error != null) ...[
            const SizedBox(height: 14),
            AuthErrorBanner(message: error!),
          ],

          // Info note
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your restaurant will be reviewed by our team before it goes live. '
                    'You\'ll be notified once approved.',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: cs.onSurface.withValues(alpha: 0.55)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          FilledButton(
            onPressed: isLoading ? null : onSubmit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : const Text('Create Account',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
