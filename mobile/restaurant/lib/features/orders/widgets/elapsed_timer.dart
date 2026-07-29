import 'dart:async';
import 'package:flutter/material.dart';

/// Displays a live elapsed time since [since], ticking every second.
/// Color changes: green → orange (after [warnAfterMinutes]) → red (after [urgentAfterMinutes]).
class ElapsedTimer extends StatefulWidget {
  final DateTime since;
  final int warnAfterMinutes;
  final int urgentAfterMinutes;

  const ElapsedTimer({
    super.key,
    required this.since,
    this.warnAfterMinutes = 10,
    this.urgentAfterMinutes = 20,
  });

  @override
  State<ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<ElapsedTimer> {
  late Timer _timer;
  late Duration _elapsed;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.since);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(widget.since);
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Color get _color {
    final mins = _elapsed.inMinutes;
    if (mins >= widget.urgentAfterMinutes) return Colors.red;
    if (mins >= widget.warnAfterMinutes) return Colors.orange;
    return Colors.green.shade700;
  }

  String get _label {
    final mins = _elapsed.inMinutes;
    final secs = _elapsed.inSeconds.remainder(60);
    if (mins == 0) return '${secs}s';
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 14, color: _color),
        const SizedBox(width: 4),
        Text(
          _label,
          style: TextStyle(
            color: _color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
