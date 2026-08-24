// Shared UI helpers used across auth screens.
import 'package:flutter/material.dart';

/// Themed input decoration used on all auth form fields.
InputDecoration authInputDec(
  BuildContext context, {
  required String label,
  required IconData icon,
  Widget? suffix,
}) {
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    prefixIcon:
        Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: 0.5)),
    suffixIcon: suffix,
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
  );
}

/// Red error banner with icon.
class AuthErrorBanner extends StatelessWidget {
  final String message;
  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: cs.onErrorContainer, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal divider with a centred label.
class AuthDivider extends StatelessWidget {
  final String label;
  const AuthDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(
          child: Divider(color: cs.outline.withValues(alpha: 0.3))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.4)),
        ),
      ),
      Expanded(
          child: Divider(color: cs.outline.withValues(alpha: 0.3))),
    ]);
  }
}
