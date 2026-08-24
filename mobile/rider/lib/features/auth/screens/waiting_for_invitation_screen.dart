import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../delivery/services/rider_service.dart';

/// Holding screen shown when the rider is authenticated but has not yet
/// received a restaurant invitation. Polls every 30 seconds and reacts
/// instantly to the 'rider:invitation' socket event (handled in auth_provider).
class WaitingForInvitationScreen extends ConsumerStatefulWidget {
  const WaitingForInvitationScreen({super.key});
  @override
  ConsumerState<WaitingForInvitationScreen> createState() =>
      _WaitingState();
}

class _WaitingState extends ConsumerState<WaitingForInvitationScreen>
    with TickerProviderStateMixin {
  Timer? _pollTimer;
  bool _checkingNow = false;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _dotsCtrl;
  late final Animation<int> _dotsAnim;

  @override
  void initState() {
    super.initState();

    // Pulsing circle behind the icon
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.88, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Animated "..." dots
    _dotsCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    )..repeat();
    _dotsAnim = StepTween(begin: 0, end: 3).animate(_dotsCtrl);

    // Start polling after a short delay
    Future.delayed(const Duration(seconds: 4), _startPolling);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _poll());
  }

  Future<void> _poll({bool manual = false}) async {
    if (_checkingNow) return;
    setState(() => _checkingNow = true);
    try {
      final res =
          await ref.read(riderServiceProvider).getPendingInvitation();
      if (!mounted) return;
      if (res != null) {
        ref.read(authProvider.notifier).onInvitationReceived(res);
        // Router will redirect to /invitation
        context.go('/invitation');
      } else if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No invitation yet — we\'ll notify you when one arrives'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (_) {
      // Network error — silent, retry on next poll
    } finally {
      if (mounted) setState(() => _checkingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final auth = ref.watch(authProvider);

    // Redirect immediately if invitation arrives via socket
    ref.listen(authProvider, (_, next) {
      if (next.invitationData != null) context.go('/invitation');
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 32),
          child: Column(children: [
            // Sign out
            Align(
              alignment: Alignment.topRight,
              child: TextButton.icon(
                onPressed: () => ref.read(authProvider.notifier).logout(),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Sign out'),
                style: TextButton.styleFrom(
                    foregroundColor: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ),

            const Spacer(),

            // Pulsing icon
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mail_outline_rounded,
                    size: 52, color: cs.primary),
              ),
            ),

            const SizedBox(height: 32),

            // Animated dots headline
            AnimatedBuilder(
              animation: _dotsAnim,
              builder: (_, __) => Text(
                'Waiting for invitation${'.' * _dotsAnim.value}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: -0.3),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'Ask a restaurant manager to invite you using your email address. '
              'You\'ll see the invitation here as soon as it arrives.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: cs.onSurface.withValues(alpha: 0.6)),
            ),

            const SizedBox(height: 36),

            // Your email chip
            if (auth.user?.email != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.email_outlined,
                        size: 15, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      auth.user!.email,
                      style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // How it works
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How it works',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: cs.onSurface)),
                  const SizedBox(height: 14),
                  _HowItWorksStep(
                    number: '1',
                    color: cs.primary,
                    text: 'Share your email with a restaurant manager',
                  ),
                  const SizedBox(height: 10),
                  _HowItWorksStep(
                    number: '2',
                    color: Colors.orange,
                    text: 'They send you an invitation from their app',
                  ),
                  const SizedBox(height: 10),
                  _HowItWorksStep(
                    number: '3',
                    color: Colors.green,
                    text:
                        'Accept it here and start receiving delivery requests',
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Check now button
            FilledButton.icon(
              onPressed: _checkingNow ? null : () => _poll(manual: true),
              icon: _checkingNow
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Check for invitation',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Auto-checks every 30 seconds',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.4)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final String number;
  final Color color;
  final String text;
  const _HowItWorksStep(
      {required this.number, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Center(
            child: Text(number,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: cs.onSurface.withValues(alpha: 0.65))),
          ),
        ),
      ],
    );
  }
}
