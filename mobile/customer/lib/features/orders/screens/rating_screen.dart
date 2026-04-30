import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/order_service.dart';

/// Full-screen rating sheet shown after an order is delivered.
/// Lets the customer rate the restaurant (1-5 stars), the rider (1-5 stars),
/// and optionally leave a text review.
class RatingScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String? restaurantName;
  final String? riderName;

  const RatingScreen({
    super.key,
    required this.orderId,
    this.restaurantName,
    this.riderName,
  });

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  int _restaurantRating = 0;
  int _riderRating = 0;
  final _reviewController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_restaurantRating == 0 && _riderRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please rate at least the restaurant or rider')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(orderServiceProvider).rate(
            widget.orderId,
            restaurantRating: _restaurantRating > 0 ? _restaurantRating : null,
            riderRating: _riderRating > 0 ? _riderRating : null,
            review: _reviewController.text.trim().isNotEmpty
                ? _reviewController.text.trim()
                : null,
          );
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit rating: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate Your Order'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !_submitted,
      ),
      body: _submitted ? _buildThankYou() : _buildForm(),
    );
  }

  Widget _buildThankYou() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 80, color: Colors.orange),
            const SizedBox(height: 20),
            const Text(
              'Thank you for your feedback!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Your rating helps us improve the experience.',
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.go('/orders'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Back to Orders'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.star_rounded, size: 40, color: Colors.orange),
                const SizedBox(height: 8),
                const Text(
                  'How was your experience?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Order #${widget.orderId.substring(0, 8).toUpperCase()}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Restaurant rating
          _RatingSection(
            title: 'Restaurant',
            subtitle: widget.restaurantName ?? 'Food quality & packaging',
            icon: Icons.restaurant,
            rating: _restaurantRating,
            onChanged: (v) => setState(() => _restaurantRating = v),
          ),
          const SizedBox(height: 24),

          // Rider rating
          _RatingSection(
            title: 'Delivery Rider',
            subtitle: widget.riderName ?? 'Speed & professionalism',
            icon: Icons.delivery_dining,
            rating: _riderRating,
            onChanged: (v) => setState(() => _riderRating = v),
          ),
          const SizedBox(height: 24),

          // Review text
          const Text(
            'Leave a review (optional)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reviewController,
            maxLines: 4,
            maxLength: 300,
            decoration: InputDecoration(
              hintText: 'Tell us what you loved or what could be better...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit Rating',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => context.go('/orders'),
              child: const Text('Skip for now',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Star rating row ───────────────────────────────────────────────────────────

class _RatingSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final int rating;
  final ValueChanged<int> onChanged;

  const _RatingSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.rating,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.orange),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: () => onChanged(star),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    star <= rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 40,
                    color: star <= rating ? Colors.orange : Colors.grey[300],
                  ),
                ),
              );
            }),
          ),
          if (rating > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                _label(rating),
                style: TextStyle(
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _label(int r) =>
      const {
        1: 'Poor',
        2: 'Fair',
        3: 'Good',
        4: 'Very Good',
        5: 'Excellent!',
      }[r] ??
      '';
}
