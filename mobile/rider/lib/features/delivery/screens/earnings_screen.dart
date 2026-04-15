import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

final _earningsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res =
      await ref.read(dioClientProvider).dio.get(ApiConstants.ridersEarnings);
  return res.data['data'] as Map<String, dynamic>;
});

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(_earningsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: earningsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final totalEarnings =
              double.parse((data['totalEarnings'] ?? 0).toString());
          final totalDeliveries = data['totalDeliveries'] as int? ?? 0;
          final deliveries = (data['deliveries'] as List<dynamic>?) ?? [];

          return Column(
            children: [
              // Summary card
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text('Total Earnings',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text(
                      'ETB ${totalEarnings.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$totalDeliveries ${totalDeliveries == 1 ? 'delivery' : 'deliveries'} completed',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),

              // Deliveries list
              Expanded(
                child: deliveries.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delivery_dining,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('No completed deliveries yet',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: deliveries.length,
                        itemBuilder: (ctx, i) {
                          final d = deliveries[i] as Map<String, dynamic>;
                          final fee =
                              double.parse((d['delivery_fee'] ?? 0).toString());
                          final date =
                              DateTime.parse(d['updated_at'] as String);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue.shade50,
                                child: const Icon(Icons.delivery_dining,
                                    color: Color(0xFF1565C0)),
                              ),
                              title: Text(
                                d['restaurant_name'] as String? ?? 'Restaurant',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d['address_line'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Colors.grey[600], fontSize: 12),
                                  ),
                                  Text(
                                    _formatDate(date),
                                    style: TextStyle(
                                        color: Colors.grey[500], fontSize: 11),
                                  ),
                                ],
                              ),
                              trailing: Text(
                                'ETB ${fee.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    color: Color(0xFF1565C0),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0)
      return 'Today ${d.toLocal().toString().substring(11, 16)}';
    if (diff.inDays == 1) return 'Yesterday';
    return '${d.day}/${d.month}/${d.year}';
  }
}
