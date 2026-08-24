import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  bool _obscure        = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).login(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final cs   = Theme.of(context).colorScheme;
    final tt   = Theme.of(context).textTheme;

    // Router handles navigation; listener here handles edge cases
    ref.listen(authProvider, (_, next) {
      if (next.status == AuthStatus.authenticated) context.go('/orders');
    });

    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background top third ──────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            height: MediaQuery.of(context).size.height * 0.38,
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
                // ── Hero section ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(Icons.storefront_rounded,
                            size: 38, color: cs.primary),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Restaurant Portal',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Sign in to manage your restaurant',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── White card ────────────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Welcome back',
                                style: tt.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Sign in to your account',
                                style: tt.bodyMedium?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.55))),
                            const SizedBox(height: 28),

                            // Email
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: authInputDec(
                                context,
                                label: 'Email address',
                                icon: Icons.email_outlined,
                              ),
                              validator: (v) =>
                                  v != null && v.contains('@')
                                      ? null
                                      : 'Enter a valid email',
                            ),
                            const SizedBox(height: 16),

                            // Password
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: authInputDec(
                                context,
                                label: 'Password',
                                icon: Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 20,
                                    color: cs.onSurface.withValues(alpha: 0.5),
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) =>
                                  v != null && v.length >= 8
                                      ? null
                                      : 'Min 8 characters',
                            ),

                            // Error banner
                            if (auth.error != null) ...[
                              const SizedBox(height: 14),
                              AuthErrorBanner(message: auth.error!),
                            ],

                            const SizedBox(height: 28),

                            // Sign In button
                            FilledButton(
                              onPressed: auth.isLoading ? null : _submit,
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
                                  : const Text('Sign In',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                            ),

                            const SizedBox(height: 24),
                            AuthDivider(label: 'or'),
                            const SizedBox(height: 20),

                            // Register link
                            OutlinedButton(
                              onPressed: () => context.push('/register'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 52),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                side: BorderSide(
                                    color: cs.outline.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                'Create a Restaurant Account',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: cs.primary),
                              ),
                            ),
                          ],
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

// (Shared auth UI helpers live in auth_widgets.dart)
