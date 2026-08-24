import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/providers/auth_provider.dart';

class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});
  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen>
    with TickerProviderStateMixin {
  Timer? _pollTimer;
  bool _polling = false;
  bool _checkingNow = false;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // How often to auto-poll (every 30s to not hammer the server)
  static const _pollInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Start polling after a short delay so screen settles first
    Future.delayed(const Duration(seconds: 3), _startPolling);
  }

  @override
  void dispose() {
    _stopPolling();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _startPolling() {
    if (_polling) return;
    _polling = true;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkStatus());
  }

  void _stopPolling() {
    _polling = false;
    _pollTimer?.cancel();
  }

  Future<void> _checkStatus({bool manual = false}) async {
    if (_checkingNow) return;
    setState(() => _checkingNow = true);
    try {
      final res =
          await ref.read(dioClientProvider).dio.get(ApiConstants.myRestaurant);
      final data = res.data['data'] as Map<String, dynamic>?;
      final status = data?['status'] as String?;

      if (!mounted) return;

      if (status == 'approved') {
        _stopPolling();
        ref.read(authProvider.notifier).onRestaurantApproved();
        // Router will automatically redirect to /orders when state updates
        context.go('/orders');
      } else if (status == 'rejected') {
        _stopPolling();
        if (mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _RejectedDialog(
              onResubmit: () {
                Navigator.pop(context);
                context.go('/setup');
              },
            ),
          );
        }
      } else if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Still under review — we\'ll notify you when approved'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (_) {
      // Network error — silently ignore, will retry on next poll
    } finally {
      if (mounted) setState(() => _checkingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
          child: Column(
            children: [
              // Sign out option top right
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextButton.icon(
                    onPressed: () =>
                        ref.read(authProvider.notifier).logout(),
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('Sign out'),
                    style: TextButton.styleFrom(
                        foregroundColor:
                            cs.onSurface.withValues(alpha: 0.5)),
                  ),
                ),
              ),

              const Spacer(),

              // ── Animated icon ─────────────────────────────────────────
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.hourglass_top_rounded,
                      size: 52, color: cs.primary),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Under Review',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your restaurant has been submitted and is being reviewed by our team. '
                'This usually takes 1–2 business days.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.55,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: 36),

              // ── What happens next ────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What happens next',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: cs.onSurface),
                    ),
                    const SizedBox(height: 16),
                    _Step(
                      icon: Icons.search_rounded,
                      color: cs.primary,
                      title: 'Review',
                      subtitle:
                          'Our team verifies your restaurant details',
                    ),
                    const SizedBox(height: 12),
                    _Step(
                      icon: Icons.notifications_active_outlined,
                      color: Colors.orange,
                      title: 'Notification',
                      subtitle:
                          'You\'ll receive an in-app notification when approved',
                    ),
                    const SizedBox(height: 12),
                    _Step(
                      icon: Icons.rocket_launch_outlined,
                      color: Colors.green,
                      title: 'Go live',
                      subtitle:
                          'Start accepting orders and managing your menu',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Restaurant name chip ──────────────────────────────────
              if (auth.user?.displayName != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: cs.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_outlined,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        auth.user!.displayName!,
                        style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w500,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              // ── Check status button ───────────────────────────────────
              FilledButton.icon(
                onPressed: _checkingNow
                    ? null
                    : () => _checkStatus(manual: true),
                icon: _checkingNow
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Check approval status',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Auto-checks every 30 seconds',
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.4)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step row ──────────────────────────────────────────────────────────────────

class _Step extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _Step({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
                      height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Rejected dialog ───────────────────────────────────────────────────────────

class _RejectedDialog extends StatelessWidget {
  final VoidCallback onResubmit;
  const _RejectedDialog({required this.onResubmit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Icon(Icons.cancel_outlined, color: cs.error, size: 40),
      title: const Text('Application Rejected',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold)),
      content: Text(
        'Unfortunately your restaurant application was not approved. '
        'Please review your details and re-submit.',
        textAlign: TextAlign.center,
        style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.65), height: 1.5),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: onResubmit,
          style: FilledButton.styleFrom(
            backgroundColor: cs.error,
            minimumSize: const Size(200, 46),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Re-submit Application'),
        ),
      ],
    );
  }
}
