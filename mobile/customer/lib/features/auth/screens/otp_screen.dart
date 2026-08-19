import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String? displayName;
  final String? phone;

  const OtpScreen({super.key, this.displayName, this.phone});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  int _resendCooldown = 60;
  Timer? _cooldownTimer;

  // Expiry countdown — codes expire in 10 minutes
  int _expirySeconds = 10 * 60;
  Timer? _expiryTimer;

  bool _locked = false; // true after too many attempts

  @override
  void initState() {
    super.initState();
    _startCooldownTimer();
    _startExpiryTimer();
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_resendCooldown <= 1) {
        t.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    setState(() => _expirySeconds = 10 * 60);
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_expirySeconds <= 1) {
        t.cancel();
        setState(() => _expirySeconds = 0);
      } else {
        setState(() => _expirySeconds--);
      }
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _expiryTimer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  String _formatExpiry() {
    final m = _expirySeconds ~/ 60;
    final s = _expirySeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _verify() async {
    if (_otp.length < 6 || _locked) return;
    await ref.read(authProvider.notifier).verifyOtp(_otp);

    // Check if locked after attempt
    final error = ref.read(authProvider).error ?? '';
    if (error.contains('Too many') || error.contains('429')) {
      setState(() => _locked = true);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0) return;
    setState(() => _locked = false);
    // Clear all boxes
    for (final c in _controllers) c.clear();
    _focusNodes[0].requestFocus();

    await ref.read(authProvider.notifier).resendOtp();
    _startCooldownTimer();
    _startExpiryTimer();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('New code sent to your email'),
            backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    // Check if locked from error message
    if (auth.error != null &&
        (auth.error!.contains('Too many') || auth.error!.contains('attempts'))) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) { if (mounted) setState(() => _locked = true); });
    }

    ref.listen(authProvider, (_, next) async {
      if (next.status == AuthStatus.authenticated) {
        if ((widget.displayName?.isNotEmpty == true) ||
            (widget.phone?.isNotEmpty == true)) {
          try {
            await ref.read(dioClientProvider).dio.put(
              ApiConstants.profile,
              data: {
                if (widget.displayName?.isNotEmpty == true)
                  'displayName': widget.displayName,
                if (widget.phone?.isNotEmpty == true) 'phone': widget.phone,
              },
            );
          } catch (_) {}
        }
        if (mounted) context.go('/home');
      }
    });

    final isExpired = _expirySeconds == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Email')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Icon(Icons.mark_email_read_outlined,
                  size: 56, color: Colors.orange),
              const SizedBox(height: 16),
              const Text('Check your email',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'We sent a 6-digit code to your email address.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),

              // ── Dev OTP banner ──────────────────────────────────────────
              if (auth.devOtp != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.developer_mode,
                          size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text('Dev OTP: ${auth.devOtp}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                              letterSpacing: 4)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Expiry countdown ────────────────────────────────────────
              if (!isExpired)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 14,
                        color: _expirySeconds < 60
                            ? Colors.red
                            : Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      'Code expires in ${_formatExpiry()}',
                      style: TextStyle(
                          fontSize: 12,
                          color: _expirySeconds < 60
                              ? Colors.red
                              : Colors.grey[500]),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                    'Your code has expired. Please request a new one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),

              const SizedBox(height: 24),

              // ── OTP boxes ───────────────────────────────────────────────
              Opacity(
                opacity: (_locked || isExpired) ? 0.4 : 1.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    6,
                    (i) => _OtpBox(
                      controller: _controllers[i],
                      focusNode: _focusNodes[i],
                      enabled: !_locked && !isExpired,
                      onChanged: (val) {
                        if (val.isNotEmpty && i < 5) {
                          _focusNodes[i + 1].requestFocus();
                        }
                        if (val.isEmpty && i > 0) {
                          _focusNodes[i - 1].requestFocus();
                        }
                        setState(() {});
                        if (_otp.length == 6 && !_locked && !isExpired) {
                          _verify();
                        }
                      },
                    ),
                  ),
                ),
              ),

              // ── Error message ───────────────────────────────────────────
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    auth.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Verify button ───────────────────────────────────────────
              ElevatedButton(
                onPressed: (_otp.length == 6 &&
                        !auth.isLoading &&
                        !_locked &&
                        !isExpired)
                    ? _verify
                    : null,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.orange,
                    disabledBackgroundColor:
                        Colors.orange.withValues(alpha: 0.4)),
                child: auth.isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Verify',
                        style:
                            TextStyle(fontSize: 16, color: Colors.white)),
              ),

              const SizedBox(height: 12),

              // ── Resend button ───────────────────────────────────────────
              TextButton(
                onPressed: _resendCooldown == 0 ? _resend : null,
                child: Text(
                  _resendCooldown > 0
                      ? 'Resend code in ${_resendCooldown}s'
                      : 'Resend code',
                  style: TextStyle(
                      color: _resendCooldown == 0
                          ? Colors.orange
                          : Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool enabled;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 52,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.orange, width: 2),
          ),
        ),
        style:
            const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        onChanged: onChanged,
      ),
    );
  }
}
