import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

/// Represents a single day's schedule.
class _DaySchedule {
  bool isOpen;
  TimeOfDay openTime;
  TimeOfDay closeTime;

  _DaySchedule({
    required this.isOpen,
    required this.openTime,
    required this.closeTime,
  });
}

class OperatingHoursScreen extends ConsumerStatefulWidget {
  const OperatingHoursScreen({super.key});

  @override
  ConsumerState<OperatingHoursScreen> createState() =>
      _OperatingHoursScreenState();
}

class _OperatingHoursScreenState extends ConsumerState<OperatingHoursScreen> {
  static const _days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  static const _dayLabels = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  final Map<String, _DaySchedule> _schedule = {
    for (final d in _days)
      d: _DaySchedule(
        isOpen: true,
        openTime: const TimeOfDay(hour: 8, minute: 0),
        closeTime: const TimeOfDay(hour: 22, minute: 0),
      ),
  };

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await ref.read(dioClientProvider).dio.get(ApiConstants.myRestaurant);
      final data = res.data['data'] as Map<String, dynamic>?;
      final hours = data?['operating_hours'] as Map<String, dynamic>?;

      if (hours != null) {
        for (final day in _days) {
          final entry = hours[day] as Map<String, dynamic>?;
          if (entry == null) continue;
          if (entry['closed'] == true) {
            _schedule[day]!.isOpen = false;
          } else {
            _schedule[day]!.isOpen = true;
            final open = _parseTime(entry['open'] as String? ?? '08:00');
            final close = _parseTime(entry['close'] as String? ?? '22:00');
            _schedule[day]!.openTime = open;
            _schedule[day]!.closeTime = close;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(String day, bool isOpen) async {
    final current =
        isOpen ? _schedule[day]!.openTime : _schedule[day]!.closeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isOpen) {
          _schedule[day]!.openTime = picked;
        } else {
          _schedule[day]!.closeTime = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{};
      for (final day in _days) {
        final s = _schedule[day]!;
        if (!s.isOpen) {
          body[day] = {'closed': true};
        } else {
          body[day] = {
            'open': _formatTime(s.openTime),
            'close': _formatTime(s.closeTime),
          };
        }
      }

      await ref.read(dioClientProvider).dio.put(
            '${ApiConstants.myRestaurant}/hours',
            data: body,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operating hours saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operating Hours'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info banner
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.green.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Once set, your restaurant will open and close automatically based on these hours.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _days.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (ctx, i) {
                      final day = _days[i];
                      final label = _dayLabels[i];
                      final s = _schedule[day]!;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            // Day name
                            SizedBox(
                              width: 90,
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color:
                                      s.isOpen ? Colors.black87 : Colors.grey,
                                ),
                              ),
                            ),
                            // Open/closed toggle
                            Switch(
                              value: s.isOpen,
                              activeThumbColor: const Color(0xFF2E7D32),
                              onChanged: (v) => setState(() => s.isOpen = v),
                            ),
                            const SizedBox(width: 8),
                            if (s.isOpen) ...[
                              // Open time picker
                              _TimePill(
                                label: _formatTime(s.openTime),
                                onTap: () => _pickTime(day, true),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text('–',
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              // Close time picker
                              _TimePill(
                                label: _formatTime(s.closeTime),
                                onTap: () => _pickTime(day, false),
                              ),
                            ] else
                              const Text(
                                'Closed',
                                style:
                                    TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Save button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Save Hours',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _TimePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TimePill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.green.shade800,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
