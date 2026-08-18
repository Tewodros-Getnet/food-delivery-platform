import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

// ── Register screen — 2 pages inside a PageView ───────────────────────────────

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _pageCtrl = PageController();

  // Step 1 fields
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _step1Key      = GlobalKey<FormState>();

  // Step 2 fields
  final _passwordCtrl  = TextEditingController();
  final _confirmCtrl   = TextEditingController();
  final _step2Key      = GlobalKey<FormState>();
  bool _obscurePass    = true;
  bool _obscureConf    = true;
  bool _agreedToTerms  = false;
  bool _onStep2        = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _goToStep2() {
    if (!_step1Key.currentState!.validate()) return;
    setState(() => _onStep2 = true);
    _pageCtrl.animateToPage(1,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _goBack() {
    if (_onStep2) {
      setState(() => _onStep2 = false);
      _pageCtrl.animateToPage(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      context.pop();
    }
  }

  Future<void> _submit() async {
    if (!_step2Key.currentState!.validate()) return;
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please agree to the Terms & Conditions'),
            backgroundColor: Colors.red),
      );
      return;
    }

    await ref.read(authProvider.notifier).register(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );

    // Store name/phone to update AFTER OTP verification succeeds.
    // We cannot update profile now because there's no JWT yet —
    // tokens are only issued after email verification.
    // The update is handled in OtpScreen after authenticated status.
    _pendingDisplayName =
        '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
    _pendingPhone = _phoneCtrl.text.trim();
  }

  // Stored for post-OTP profile update
  String _pendingDisplayName = '';
  String _pendingPhone = '';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    ref.listen(authProvider, (_, next) {
      if (next.status == AuthStatus.pendingVerification) {
        context.go('/verify-otp', extra: {
          'displayName': _pendingDisplayName,
          'phone': _pendingPhone,
        });
      }
      if (next.status == AuthStatus.authenticated) {
        context.go('/home');
      }
    });

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Back button ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: _goBack,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_left,
                      color: Colors.white, size: 24),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Pages ────────────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Step1(
                    formKey: _step1Key,
                    firstNameCtrl: _firstNameCtrl,
                    lastNameCtrl: _lastNameCtrl,
                    emailCtrl: _emailCtrl,
                    phoneCtrl: _phoneCtrl,
                    onContinue: _goToStep2,
                  ),
                  _Step2(
                    formKey: _step2Key,
                    passwordCtrl: _passwordCtrl,
                    confirmCtrl: _confirmCtrl,
                    obscurePass: _obscurePass,
                    obscureConf: _obscureConf,
                    agreedToTerms: _agreedToTerms,
                    isLoading: auth.isLoading,
                    error: auth.error,
                    onTogglePass: () =>
                        setState(() => _obscurePass = !_obscurePass),
                    onToggleConf: () =>
                        setState(() => _obscureConf = !_obscureConf),
                    onToggleTerms: (v) =>
                        setState(() => _agreedToTerms = v ?? false),
                    onSubmit: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 1: Personal info ─────────────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onContinue;

  const _Step1({
    required this.formKey,
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create new account',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(children: [
              Text('Already have an account? ',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              GestureDetector(
                onTap: () => context.go('/login'),
                child: const Text('Sign in',
                    style: TextStyle(
                        color: Color(0xFFCC1A1A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 32),

            _label('First Name'),
            _field(firstNameCtrl, 'Enter your first name',
                validator: (v) =>
                    v != null && v.trim().isNotEmpty ? null : 'Required'),
            const SizedBox(height: 20),

            _label('Last Name'),
            _field(lastNameCtrl, 'Enter your last name',
                validator: (v) =>
                    v != null && v.trim().isNotEmpty ? null : 'Required'),
            const SizedBox(height: 20),

            _label('Email Address'),
            _field(emailCtrl, 'Enter your email address',
                keyboard: TextInputType.emailAddress,
                validator: (v) => v != null && v.contains('@')
                    ? null
                    : 'Enter a valid email'),
            const SizedBox(height: 20),

            _label('Phone Number'),
            // Phone row with +251 prefix
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: const Text('+251',
                      style: TextStyle(color: Colors.white, fontSize: 15)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'e.g. 999-999-999',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[700]!)),
                      focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue, width: 2)),
                      errorBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.red)),
                      focusedErrorBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.red, width: 2)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: const Text('Continue',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Reset your password',
                    style: TextStyle(
                        color: Color(0xFFCC1A1A), fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[600]),
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[700]!)),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue, width: 2)),
          errorBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.red)),
          focusedErrorBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.red, width: 2)),
          errorStyle: const TextStyle(color: Colors.red),
        ),
      );
}

// ── Step 2: Password ──────────────────────────────────────────────────────────

class _Step2 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final bool obscurePass;
  final bool obscureConf;
  final bool agreedToTerms;
  final bool isLoading;
  final String? error;
  final VoidCallback onTogglePass;
  final VoidCallback onToggleConf;
  final ValueChanged<bool?> onToggleTerms;
  final VoidCallback onSubmit;

  const _Step2({
    required this.formKey,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.obscurePass,
    required this.obscureConf,
    required this.agreedToTerms,
    required this.isLoading,
    required this.error,
    required this.onTogglePass,
    required this.onToggleConf,
    required this.onToggleTerms,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Almost Done!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Set password',
                style: TextStyle(color: Colors.grey[500], fontSize: 14)),
            const SizedBox(height: 36),

            _label('Password'),
            TextFormField(
              controller: passwordCtrl,
              obscureText: obscurePass,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              validator: (v) =>
                  v != null && v.length >= 8 ? null : 'Min 8 characters',
              decoration: _decor('', suffix: IconButton(
                icon: Icon(
                    obscurePass
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.grey[500],
                    size: 20),
                onPressed: onTogglePass,
              )),
            ),
            const SizedBox(height: 24),

            _label('Confirm password'),
            TextFormField(
              controller: confirmCtrl,
              obscureText: obscureConf,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              validator: (v) => v == passwordCtrl.text
                  ? null
                  : 'Passwords do not match',
              decoration: _decor('', suffix: IconButton(
                icon: Icon(
                    obscureConf
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.grey[500],
                    size: 20),
                onPressed: onToggleConf,
              )),
            ),
            const SizedBox(height: 24),

            // Terms checkbox
            Row(
              children: [
                Checkbox(
                  value: agreedToTerms,
                  onChanged: onToggleTerms,
                  activeColor: const Color(0xFFCC1A1A),
                  side: BorderSide(color: Colors.grey[600]!),
                ),
                const Text('I agree to the ',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                const Text('Terms & Conditions',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),

            if (error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            ],

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCC1A1A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Create my account',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      );

  InputDecoration _decor(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[600]),
        suffixIcon: suffix,
        enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.grey[700]!)),
        focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2)),
        errorBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.red)),
        focusedErrorBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.red, width: 2)),
        errorStyle: const TextStyle(color: Colors.red),
      );
}
