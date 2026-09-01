import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // Step 1 — Account
  final _step1Key     = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure       = true;

  // Step 2 — Personal info
  final _step2Key   = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _phoneCtrl  = TextEditingController();

  int _step = 0;
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  static const _totalSteps = 2;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));
    _slideAnim = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _goToStep(int next) {
    setState(() => _step = next);
    _slideCtrl.forward(from: 0);
  }

  Future<void> _submit() async {
    if (!_step2Key.currentState!.validate()) return;
    await ref.read(authProvider.notifier).register(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          displayName: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final cs   = Theme.of(context).colorScheme;

    ref.listen(authProvider, (_, next) {
      if (next.status == AuthStatus.pendingVerification) {
        context.go('/verify-otp');
      }
    });

    return Scaffold(
      body: Stack(children: [
        // Gradient band
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
          child: Column(children: [
            // ── Top bar ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () =>
                      _step == 0 ? context.pop() : _goToStep(_step - 1),
                ),
                const Spacer(),
                // Step pills
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
                        color: (active || done)
                            ? Colors.white
                            : Colors.white38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ]),
            ),

            // Hero icon + heading
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(children: [
                Container(
                  width: 68, height: 68,
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
                        : Icons.badge_outlined,
                    size: 32, color: cs.primary,
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Column(
                    key: ValueKey(_step),
                    children: [
                      Text(
                        _step == 0
                            ? 'Create your account'
                            : 'Tell us about yourself',
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
                            ? 'Step 1 of 2 — Login credentials'
                            : 'Step 2 of 2 — Personal details',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 20),

            // ── White card ──────────────────────────────────────────────────
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
                  position: _slideAnim,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _step == 0
                          ? _StepAccount(
                              key: const ValueKey(0),
                              formKey: _step1Key,
                              emailCtrl: _emailCtrl,
                              passwordCtrl: _passwordCtrl,
                              obscure: _obscure,
                              onToggle: () =>
                                  setState(() => _obscure = !_obscure),
                              error: auth.error,
                              isLoading: auth.isLoading,
                              onNext: () {
                                if (_step1Key.currentState!.validate()) {
                                  _goToStep(1);
                                }
                              },
                              onSignIn: () => context.pop(),
                            )
                          : _StepPersonal(
                              key: const ValueKey(1),
                              formKey: _step2Key,
                              nameCtrl: _nameCtrl,
                              phoneCtrl: _phoneCtrl,
                              error: auth.error,
                              isLoading: auth.isLoading,
                              onSubmit: _submit,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Step 1 — Account credentials ─────────────────────────────────────────────

class _StepAccount extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final VoidCallback onToggle;
  final String? error;
  final bool isLoading;
  final VoidCallback onNext;
  final VoidCallback onSignIn;

  const _StepAccount({
    super.key,
    required this.formKey,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.onToggle,
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
          Text('How you\'ll sign in to Tana Driver',
              style: tt.bodySmall
                  ?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 24),

          TextFormField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: authInputDec(context,
                label: 'Email address', icon: Icons.email_outlined),
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
                onPressed: onToggle,
              ),
            ),
            validator: (v) =>
                v != null && v.length >= 8 ? null : 'Min 8 characters',
          ),

          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Use at least 8 characters with a mix of letters and numbers.',
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
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Continue',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Already a rider? ',
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

// ── Step 2 — Personal info ────────────────────────────────────────────────────

class _StepPersonal extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final String? error;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _StepPersonal({
    super.key,
    required this.formKey,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.error,
    required this.isLoading,
    required this.onSubmit,
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
          Text('Personal details',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Shown to restaurants and customers',
              style: tt.bodySmall
                  ?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 24),

          TextFormField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: authInputDec(context,
                label: 'Full name',
                icon: Icons.person_outline_rounded,
                hint: 'e.g. Abebe Girma'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onSubmit(),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: authInputDec(context,
                label: 'Phone number',
                icon: Icons.phone_outlined,
                hint: 'e.g. 0911234567'),
            validator: (v) =>
                v != null && v.length >= 9 ? null : 'Enter a valid phone number',
          ),

          const SizedBox(height: 20),

          // Info note
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
                    'After verifying your email a restaurant can send you an invitation. '
                    'You\'ll need to accept it before you can start delivering.',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: cs.onSurface.withValues(alpha: 0.55)),
                  ),
                ),
              ],
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 14),
            AuthErrorBanner(message: error!),
          ],

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
