import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

// Period options
enum EarningsPeriod { week, month, all }

// Provider family — keyed by period so each tab has its own cache
// Exposed for testing — override in ProviderScope to avoid real network calls.
final earningsProvider =
    FutureProvider.family<Map<String, dynamic>, EarningsPeriod>((ref, period) async {
  final now = DateTime.now();
  String? startDate;

  switch (period) {
    case EarningsPeriod.week:
      startDate = now.subtract(const Duration(days: 7)).toIso8601String();
      break;
    case EarningsPeriod.month:
      startDate = now.subtract(const Duration(days: 30)).toIso8601String();
      break;
    case EarningsPeriod.all:
      startDate = null;
      break;
  }

  final res = await ref.read(dioClientProvider).dio.get(
    ApiConstants.ridersEarnings,
    queryParameters: {
      if (startDate != null) 'startDate': startDate,
    },
  );
  return res.data['data'] as Map<String, dynamic>;
});

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    (label: 'This Week', period: EarningsPeriod.week),
    (label: 'This Month', period: EarningsPeriod.month),
    (label: 'All Time', period: EarningsPeriod.all),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((t) => _EarningsTab(period: t.period)).toList(),
      ),
    );
  }
}

class _EarningsTab extends ConsumerWidget {
  final EarningsPeriod period;
  const _EarningsTab({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(earningsProvider(period));

    return earningsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text('Error: $e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.refresh(earningsProvider(period)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (data) {
        final totalEarnings =
            double.parse((data['totalEarnings'] ?? 0).toString());
        final totalDeliveries = data['totalDeliveries'] as int? ?? 0;
        final deliveries = (data['deliveries'] as List<dynamic>?) ?? [];

        return RefreshIndicator(
          onRefresh: () => ref.refresh(earningsProvider(period).future),
          child: Column(
            children: [
              // Summary card
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      EarningsPeriodLabel(period),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ETB ${totalEarnings.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.delivery_dining,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '$totalDeliveries ${totalDeliveries == 1 ? 'delivery' : 'deliveries'} completed',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                    if (totalDeliveries > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Avg ETB ${(totalEarnings / totalDeliveries).toStringAsFixed(2)} / delivery',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Deliveries list
              Expanded(
                child: deliveries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delivery_dining,
                                size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'No deliveries ${EarningsPeriodLabel(period).toLowerCase()}',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 15),
                            ),
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
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
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
          ),
        );
      },
    );
  }

  String EarningsPeriodLabel(EarningsPeriod p) {
    switch (p) {
      case EarningsPeriod.week:
        return 'This Week';
      case EarningsPeriod.month:
        return 'This Month';
      case EarningsPeriod.all:
        return 'All Time';
    }
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
