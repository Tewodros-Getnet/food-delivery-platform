import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../delivery/services/rider_service.dart';

/// Full-screen invitation view — shown when the rider has a pending invitation
/// from a restaurant. Real platforms (Lalamove, Bosta) use a dedicated screen
/// so the rider can read the restaurant details before committing.
class InvitationScreen extends ConsumerStatefulWidget {
  const InvitationScreen({super.key});
  @override
  ConsumerState<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends ConsumerState<InvitationScreen>
    with TickerProviderStateMixin {
  bool _responding = false;
  String? _error;

  late final AnimationController _enterCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideUpAnim;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slideUpAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  Future<void> _respond(bool accept) async {
    final invitation = ref.read(authProvider).invitationData;
    final id = invitation?['id'] as String?;
    if (id == null) return;

    setState(() { _responding = true; _error = null; });
    try {
      await ref.read(riderServiceProvider).respondInvitation(id, accept);
      if (!mounted) return;

      if (accept) {
        // Mark invitation as accepted in state so the router sends to /home
        ref.read(authProvider.notifier).onInvitationAccepted();
        _showSuccessSheet();
      } else {
        // Declined — clear invitation and go back to waiting screen
        ref.read(authProvider.notifier).onInvitationDeclined();
        context.go('/waiting');
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _responding = false;
      });
    }
  }

  void _showSuccessSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 28),
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 44),
            ),
            const SizedBox(height: 20),
            const Text(
              'You\'re in! 🎉',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ve joined the restaurant\'s delivery team. '
              'Go online when you\'re ready to start receiving orders.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/home');
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Start Delivering',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final invitation = ref.watch(authProvider).invitationData;
    final restName   = invitation?['restaurant_name'] as String? ?? 'Restaurant';
    final restAddr   = invitation?['restaurant_address'] as String?;
    final restCity   = invitation?['restaurant_city'] as String?;

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideUpAnim,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                children: [
                  // Sign out top right
                  Align(
                    alignment: Alignment.topRight,
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

                  const Spacer(),

                  // ── Restaurant card ──────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: cs.primary.withValues(alpha: 0.2),
                          width: 1.5),
                    ),
                    child: Column(
                      children: [
                        // Icon
                        Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.storefront_rounded,
                              size: 36, color: cs.primary),
                        ),
                        const SizedBox(height: 16),

                        // "wants you to join"
                        Text(
                          restName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),

                        if (restAddr != null || restCity != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 14,
                                  color: cs.onSurface.withValues(alpha: 0.5)),
                              const SizedBox(width: 4),
                              Text(
                                [restAddr, restCity]
                                    .where((s) => s != null && s.isNotEmpty)
                                    .join(', '),
                                style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface
                                        .withValues(alpha: 0.55)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],

                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'wants you to join their delivery team',
                            style: TextStyle(
                                fontSize: 13,
                                color: cs.primary,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── What joining means ───────────────────────────────────
                  _BenefitRow(
                    icon: Icons.delivery_dining_rounded,
                    color: cs.primary,
                    text:
                        'Receive delivery requests from this restaurant\'s orders',
                  ),
                  const SizedBox(height: 12),
                  _BenefitRow(
                    icon: Icons.schedule_rounded,
                    color: Colors.orange,
                    text:
                        'Work flexible hours — go online and offline whenever you want',
                  ),
                  const SizedBox(height: 12),
                  _BenefitRow(
                    icon: Icons.payments_outlined,
                    color: Colors.green,
                    text:
                        'Earn a delivery fee for every completed order',
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!,
                          style: TextStyle(
                              color: cs.onErrorContainer, fontSize: 13)),
                    ),
                  ],

                  const Spacer(),

                  // ── Action buttons ───────────────────────────────────────
                  if (_responding)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: () => _respond(true),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          color: Colors.white, size: 20),
                      label: const Text('Accept & Join Team',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _respond(false),
                      icon: Icon(Icons.close_rounded,
                          color: cs.error, size: 18),
                      label: Text('Decline',
                          style: TextStyle(
                              color: cs.error,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        side: BorderSide(
                            color: cs.error.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small benefit row widget ──────────────────────────────────────────────────

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _BenefitRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: cs.onSurface.withValues(alpha: 0.7))),
          ),
        ),
      ],
    );
  }
}
