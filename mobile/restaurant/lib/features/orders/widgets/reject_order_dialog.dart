import 'package:flutter/material.dart';

/// Dialog that requires the restaurant owner to enter a rejection reason
/// before submitting. The confirm button is disabled until the field is non-empty.
class RejectOrderDialog extends StatefulWidget {
  final String orderId;
  final Future<void> Function(String reason) onConfirm;

  const RejectOrderDialog({
    super.key,
    required this.orderId,
    required this.onConfirm,
  });

  @override
  State<RejectOrderDialog> createState() => _RejectOrderDialogState();
}

class _RejectOrderDialogState extends State<RejectOrderDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _controller.text.trim();
    if (reason.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.onConfirm(reason);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Text(
            'Reject Order #${widget.orderId.substring(0, 8)}',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Please provide a reason. The customer will be notified and refunded.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !_loading,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. Item unavailable, kitchen closed...',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed:
              (_controller.text.trim().isEmpty || _loading) ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Reject Order',
                  style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
