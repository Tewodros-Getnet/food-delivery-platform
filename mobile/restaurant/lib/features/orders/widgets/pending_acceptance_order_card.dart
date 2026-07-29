import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import 'countdown_timer.dart';
import 'reject_order_dialog.dart';

/// Card shown in the "New Orders" section for orders awaiting restaurant acceptance.
/// Displays order summary, countdown timer, and Accept/Reject buttons.
class PendingAcceptanceOrderCard extends ConsumerStatefulWidget {
  final OrderModel order;
  final VoidCallback onAccepted;
  final VoidCallback onRejected;

  const PendingAcceptanceOrderCard({
    super.key,
    required this.order,
    required this.onAccepted,
    required this.onRejected,
  });

  @override
  ConsumerState<PendingAcceptanceOrderCard> createState() =>
      _PendingAcceptanceOrderCardState();
}

class _PendingAcceptanceOrderCardState
    extends ConsumerState<PendingAcceptanceOrderCard> {
  bool _acceptLoading = false;

  Future<void> _accept() async {
    setState(() => _acceptLoading = true);
    try {
      await ref.read(orderServiceProvider).acceptOrder(widget.order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order accepted — start preparing!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onAccepted();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _acceptLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept: $e')),
        );
      }
    }
  }

  Future<void> _reject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RejectOrderDialog(
        orderId: widget.order.id,
        onConfirm: (reason) =>
            ref.read(orderServiceProvider).rejectOrder(widget.order.id, reason),
      ),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order rejected. Customer will be refunded.'),
          backgroundColor: Colors.orange,
        ),
      );
      widget.onRejected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isExpired = order.acceptanceDeadline != null &&
        order.acceptanceDeadline!.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isExpired ? Colors.grey : Colors.orange,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: order ID + countdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.id.substring(0, 8)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Text(
                        'Awaiting your response',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (order.acceptanceDeadline != null)
                  CountdownTimer(deadline: order.acceptanceDeadline!),
              ],
            ),
            const Divider(height: 20),
            // Order details
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 16, color: Colors.black54),
                const SizedBox(width: 6),
                Text(
                  'Total: ETB ${order.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.black54),
                const SizedBox(width: 6),
                Text(
                  'Placed at ${order.createdAt.toLocal().toString().substring(11, 16)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
            if (!isExpired) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  // Reject button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _acceptLoading ? null : _reject,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Accept button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _acceptLoading ? null : _accept,
                      icon: _acceptLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 16),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'This order has expired and will be auto-cancelled.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
