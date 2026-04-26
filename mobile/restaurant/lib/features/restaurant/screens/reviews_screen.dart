import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

class RestaurantReviewsScreen extends ConsumerStatefulWidget {
  const RestaurantReviewsScreen({super.key});

  @override
  ConsumerState<RestaurantReviewsScreen> createState() =>
      _RestaurantReviewsScreenState();
}

class _RestaurantReviewsScreenState
    extends ConsumerState<RestaurantReviewsScreen> {
  List<Map<String, dynamic>> _ratings = [];
  bool _loading = true;
  String? _restaurantId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioClientProvider).dio;
      // Get restaurant ID first
      final rRes = await dio.get(ApiConstants.myRestaurant);
      _restaurantId =
          (rRes.data['data'] as Map<String, dynamic>)['id'] as String?;

      if (_restaurantId != null) {
        final res =
            await dio.get('${ApiConstants.restaurants}/$_restaurantId/ratings');
        final list = res.data['data'] as List<dynamic>;
        setState(() {
          _ratings = list.map((e) => e as Map<String, dynamic>).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reply(String ratingId, String existingReply) async {
    final ctrl = TextEditingController(text: existingReply);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reply to Review'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Write your response...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32)),
            child:
                const Text('Post Reply', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || ctrl.text.trim().isEmpty) return;

    try {
      await ref.read(dioClientProvider).dio.post(
        '${ApiConstants.restaurants}/ratings/$ratingId/reply',
        data: {'reply': ctrl.text.trim()},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply posted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Reviews'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ratings.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border, size: 48, color: Colors.black26),
                      SizedBox(height: 12),
                      Text('No reviews yet',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _ratings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final r = _ratings[i];
                      final score = (r['rating'] as num?)?.toInt() ?? 0;
                      final review = r['review'] as String?;
                      final name = r['customer_name'] as String? ?? 'Customer';
                      final reply = r['reply'] as String?;
                      final ratingId = r['id'] as String;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Customer + stars
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.orange.shade100,
                                    child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  Row(
                                    children: List.generate(
                                      5,
                                      (j) => Icon(
                                        j < score
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: Colors.amber,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (review != null && review.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(review,
                                    style: TextStyle(
                                        color: Colors.grey[700], fontSize: 13)),
                              ],
                              // Existing reply
                              if (reply != null && reply.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.green.shade100),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Icon(Icons.storefront,
                                            size: 13,
                                            color: Colors.green.shade700),
                                        const SizedBox(width: 4),
                                        Text('Your reply',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade700)),
                                      ]),
                                      const SizedBox(height: 4),
                                      Text(reply,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green.shade900)),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              // Reply / Edit reply button
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _reply(ratingId, reply ?? ''),
                                  icon: Icon(
                                    reply != null && reply.isNotEmpty
                                        ? Icons.edit
                                        : Icons.reply,
                                    size: 16,
                                  ),
                                  label: Text(
                                    reply != null && reply.isNotEmpty
                                        ? 'Edit Reply'
                                        : 'Reply',
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF2E7D32),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
