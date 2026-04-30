import 'package:flutter/material.dart';

/// Shown when a network request fails.
/// Detects Render cold-start timeouts and shows a friendlier message.
class RetryWidget extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final String? customMessage;

  const RetryWidget({
    super.key,
    required this.error,
    required this.onRetry,
    this.customMessage,
  });

  bool get _isColdStart {
    final msg = error.toString().toLowerCase();
    return msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connect');
  }

  @override
  Widget build(BuildContext context) {
    final isCold = _isColdStart;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCold ? Icons.cloud_off_outlined : Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isCold ? 'Server is waking up...' : 'Something went wrong',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              customMessage ??
                  (isCold
                      ? 'Our server takes ~30 seconds to start after inactivity. Please try again.'
                      : error.toString()),
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Try Again',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size(160, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
