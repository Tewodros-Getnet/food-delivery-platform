import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _ctrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  int _cooldown = 60;
  Timer? _timer;
  bool _resending = false;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween(begin: 0.0, end: 8.0)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shakeCtrl.dispose();
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    super.dispose();
  }

  String get _otp => _ctrls.map((c) => c.text).join();

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _cooldown = 0);
      } else {
        if (mounted) setState(() => _cooldown--);
      }
    });
  }

  Future<void> _verify() async {
    if (_otp.length < 6) return;
    await ref.read(authProvider.notifier).verifyOtp(_otp);
    // If error, shake + clear
    final err = ref.read(authProvider).error;
    if (err != null && mounted) {
      _shakeCtrl.forward(from: 0);
      for (final c in _ctrls) c.clear();
      _nodes[0].requestFocus();
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _resending) return;
    setState(() => _resending = true);
    await ref.read(authProvider.notifier).resendOtp();
    _startCooldown();
    setState(() => _resending = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('A new code was sent to your email'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final cs   = Theme.of(context).colorScheme;

    ref.listen(authProvider, (_, next) {
      if (next.status == AuthStatus.authenticated) {
        // Router redirect handles destination (could be /setup or /orders)
        context.go('/orders');
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          // Gradient top band
          Positioned(
            top: 0, left: 0, right: 0,
            height: MediaQuery.of(context).size.height * 0.32,
            child: Container(
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
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Back button + title
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                ),

                // Hero icon + heading
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
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
                        child: Icon(Icons.mark_email_read_outlined,
                            size: 34, color: cs.primary),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Check your email',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'We sent a 6-digit verification code',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // White card
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 20,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Dev mode OTP banner
                          if (auth.devOtp != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.developer_mode_rounded,
                                      size: 16, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Dev OTP: ${auth.devOtp}',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                      letterSpacing: 5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          Text('Enter the code',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            'Type the 6-digit code from your email. '
                            'It expires in 10 minutes.',
                            style: TextStyle(
                                fontSize: 13,
                                color:
                                    cs.onSurface.withValues(alpha: 0.5),
                                height: 1.4),
                          ),
                          const SizedBox(height: 28),

                          // OTP boxes with shake on error
                          AnimatedBuilder(
                            animation: _shakeAnim,
                            builder: (_, child) => Transform.translate(
                              offset: Offset(_shakeAnim.value, 0),
                              child: child,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(
                                6,
                                (i) => _OtpBox(
                                  controller: _ctrls[i],
                                  focusNode: _nodes[i],
                                  hasError: auth.error != null,
                                  onChanged: (val) {
                                    if (val.isNotEmpty && i < 5) {
                                      _nodes[i + 1].requestFocus();
                                    }
                                    if (_otp.length == 6) _verify();
                                  },
                                  onBackspace: () {
                                    if (_ctrls[i].text.isEmpty && i > 0) {
                                      _nodes[i - 1].requestFocus();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),

                          // Error message
                          if (auth.error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded,
                                      size: 16,
                                      color: cs.onErrorContainer),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      auth.error!,
                                      style: TextStyle(
                                          color: cs.onErrorContainer,
                                          fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 28),

                          // Verify button
                          FilledButton(
                            onPressed: (_otp.length < 6 || auth.isLoading)
                                ? null
                                : _verify,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: auth.isLoading
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white))
                                : const Text('Verify Email',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                          ),

                          const SizedBox(height: 20),

                          // Resend
                          Center(
                            child: _cooldown > 0
                                ? RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: cs.onSurface
                                              .withValues(alpha: 0.5)),
                                      children: [
                                        const TextSpan(text: 'Resend code in '),
                                        TextSpan(
                                          text: '${_cooldown}s',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: cs.primary),
                                        ),
                                      ],
                                    ),
                                  )
                                : TextButton(
                                    onPressed: _resending ? null : _resend,
                                    child: _resending
                                        ? SizedBox(
                                            width: 16, height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: cs.primary))
                                        : Text('Resend code',
                                            style: TextStyle(
                                                color: cs.primary,
                                                fontWeight: FontWeight.w600)),
                                  ),
                          ),
                        ],
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

// ── Single OTP digit box ──────────────────────────────────────────────────────

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 46,
      height: 56,
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) {
          if (event is RawKeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: cs.onSurface),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: hasError
                ? cs.errorContainer.withValues(alpha: 0.4)
                : focusNode.hasFocus
                    ? cs.primaryContainer.withValues(alpha: 0.5)
                    : cs.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: hasError
                      ? cs.error.withValues(alpha: 0.5)
                      : cs.outline.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
