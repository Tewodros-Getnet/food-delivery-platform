import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

class RestaurantAnalyticsScreen extends ConsumerStatefulWidget {
  const RestaurantAnalyticsScreen({super.key});

  @override
  ConsumerState<RestaurantAnalyticsScreen> createState() =>
      _RestaurantAnalyticsScreenState();
}

class _RestaurantAnalyticsScreenState
    extends ConsumerState<RestaurantAnalyticsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(dioClientProvider)
          .dio
          .get(ApiConstants.myRestaurantAnalytics);
      setState(() {
        _data = res.data['data'] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildKpiRow(),
                      const SizedBox(height: 20),
                      _buildRatingCard(),
                      const SizedBox(height: 20),
                      _buildTopItemsCard(),
                      const SizedBox(height: 20),
                      _buildOrdersByStatusCard(),
                      const SizedBox(height: 20),
                      _buildRecentOrdersCard(),
                    ],
                  ),
                ),
    );
  }

  // ── KPI row: Today / Week / Month ─────────────────────────────────────────
  Widget _buildKpiRow() {
    final today = _data!['today'] as Map<String, dynamic>;
    final week = _data!['week'] as Map<String, dynamic>;
    final month = _data!['month'] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Performance',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _KpiCard(
              label: 'Today',
              orders: today['orders'] as int,
              revenue: (today['revenue'] as num).toDouble(),
              color: Colors.blue,
            )),
            const SizedBox(width: 8),
            Expanded(
                child: _KpiCard(
              label: '7 Days',
              orders: week['orders'] as int,
              revenue: (week['revenue'] as num).toDouble(),
              color: Colors.orange,
            )),
            const SizedBox(width: 8),
            Expanded(
                child: _KpiCard(
              label: '30 Days',
              orders: month['orders'] as int,
              revenue: (month['revenue'] as num).toDouble(),
              color: const Color(0xFF2E7D32),
            )),
          ],
        ),
      ],
    );
  }

  // ── Rating + avg prep time ────────────────────────────────────────────────
  Widget _buildRatingCard() {
    final rating = (_data!['restaurantRating'] as num?)?.toDouble() ?? 0.0;
    final avgPrep = (_data!['avgPrepTimeMinutes'] as num?)?.toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Average Rating',
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const Text(' / 5',
                        style: TextStyle(color: Colors.black38, fontSize: 14)),
                  ],
                ),
              ],
            ),
          ),
          if (avgPrep != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Avg Prep Time',
                      style: TextStyle(color: Colors.black54, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        '${avgPrep.toStringAsFixed(0)} min',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Top menu items ────────────────────────────────────────────────────────
  Widget _buildTopItemsCard() {
    final items = (_data!['topItems'] as List<dynamic>?) ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      title: 'Top Items (30 days)',
      child: Column(
        children: items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value as Map<String, dynamic>;
          final name = item['item_name'] as String;
          final qty = item['total_quantity'].toString();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: i == 0
                        ? Colors.amber
                        : i == 1
                            ? Colors.grey.shade400
                            : Colors.brown.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(name, style: const TextStyle(fontSize: 13))),
                Text(
                  '$qty ordered',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Orders by status ──────────────────────────────────────────────────────
  Widget _buildOrdersByStatusCard() {
    final statuses = (_data!['ordersByStatus'] as List<dynamic>?) ?? [];
    if (statuses.isEmpty) return const SizedBox.shrink();

    final statusColors = <String, Color>{
      'delivered': Colors.green,
      'cancelled': Colors.red,
      'confirmed': Colors.blue,
      'ready_for_pickup': Colors.orange,
      'rider_assigned': Colors.purple,
      'picked_up': Colors.teal,
      'pending_acceptance': Colors.amber,
      'pending_payment': Colors.grey,
      'payment_failed': Colors.red,
    };

    return _SectionCard(
      title: 'Orders by Status (30 days)',
      child: Column(
        children: statuses.map((s) {
          final status = s['status'] as String;
          final count = int.tryParse(s['count'].toString()) ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColors[status] ?? Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  '$count',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Recent orders ─────────────────────────────────────────────────────────
  Widget _buildRecentOrdersCard() {
    final orders = (_data!['recentOrders'] as List<dynamic>?) ?? [];
    if (orders.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      title: 'Recent Orders',
      child: Column(
        children: orders.map((o) {
          final order = o as Map<String, dynamic>;
          final status = order['status'] as String;
          final total = double.tryParse(order['total'].toString()) ?? 0;
          final summary = order['items_summary'] as String? ?? '';
          final createdAt = DateTime.tryParse(order['created_at'] as String);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${(order['id'] as String).substring(0, 8)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            fontFamily: 'monospace'),
                      ),
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'ETB ${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    if (createdAt != null)
                      Text(
                        '${createdAt.toLocal().toString().substring(11, 16)}',
                        style: const TextStyle(
                            color: Colors.black38, fontSize: 11),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: status == 'delivered'
                            ? Colors.green.shade50
                            : status == 'cancelled'
                                ? Colors.red.shade50
                                : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status.replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 10,
                          color: status == 'delivered'
                              ? Colors.green.shade700
                              : status == 'cancelled'
                                  ? Colors.red.shade700
                                  : Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final int orders;
  final double revenue;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.orders,
    required this.revenue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            '$orders',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            'orders',
            style: TextStyle(color: color.withAlpha(180), fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            'ETB ${revenue.toStringAsFixed(0)}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color.withAlpha(200)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
