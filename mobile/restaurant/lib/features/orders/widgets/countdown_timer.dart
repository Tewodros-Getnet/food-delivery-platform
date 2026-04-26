import 'dart:async';
import 'package:flutter/material.dart';

/// Displays a MM:SS countdown to [deadline].
/// Shows "Expired" in red when the deadline has passed.
class CountdownTimer extends StatefulWidget {
  final DateTime deadline;

  const CountdownTimer({super.key, required this.deadline});

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.deadline.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = widget.deadline.difference(DateTime.now());
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining.isNegative) {
      return const Text(
        'Expired',
        style: TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      );
    }

    final minutes =
        _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final isUrgent = _remaining.inSeconds <= 60;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.timer_outlined,
          size: 14,
          color: isUrgent ? Colors.red : Colors.orange,
        ),
        const SizedBox(width: 4),
        Text(
          '$minutes:$seconds',
          style: TextStyle(
            color: isUrgent ? Colors.red : Colors.orange,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
