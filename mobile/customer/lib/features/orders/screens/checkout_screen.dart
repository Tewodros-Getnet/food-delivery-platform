import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../cart/providers/cart_provider.dart';
import '../services/order_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

final _addressesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioClientProvider).dio.get(ApiConstants.addresses);
  final list = res.data['data'] as List<dynamic>;
  return list.map((e) => e as Map<String, dynamic>).toList();
});

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isLoading = false;
  String? _error;
  String? _selectedAddressId;

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);
    if (cart.restaurantId == null || cart.items.isEmpty) return;
    if (_selectedAddressId == null) {
      setState(() => _error = 'Please select a delivery address');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await ref.read(orderServiceProvider).createOrder(
            restaurantId: cart.restaurantId!,
            deliveryAddressId: _selectedAddressId!,
            items: cart.items,
          );
      final paymentUrl = result['paymentUrl'] as String?;
      final orderId = (result['order'] as Map<String, dynamic>)['id'] as String;
      if (paymentUrl != null) {
        final uri = Uri.parse(paymentUrl);
        final launched =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && mounted) {
          setState(() => _error = 'Could not open payment page. Try again.');
          return;
        }
      }
      ref.read(cartProvider.notifier).clear();
      if (mounted) context.push('/order/$orderId/track');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final addressesAsync = ref.watch(_addressesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Order Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...cart.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${item.menuItem.name} x${item.quantity}'),
                      Text('ETB ${item.subtotal.toStringAsFixed(2)}'),
                    ]),
              )),
          const Divider(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('ETB ${cart.subtotal.toStringAsFixed(2)}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 20),
          const Text('Delivery Address',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          addressesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Failed to load addresses: $e',
                style: const TextStyle(color: Colors.red)),
            data: (addresses) => addresses.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        const Text('No saved addresses.',
                            style: TextStyle(color: Colors.grey)),
                        TextButton(
                          onPressed: () => context.push('/addresses'),
                          child: const Text('Add an address first'),
                        ),
                      ])
                : Column(
                    children: addresses
                        .map((a) => RadioListTile<String>(
                              title: Text(a['label'] as String? ?? 'Address'),
                              subtitle: Text(a['address_line'] as String),
                              value: a['id'] as String,
                              groupValue: _selectedAddressId,
                              onChanged: (v) =>
                                  setState(() => _selectedAddressId = v),
                            ))
                        .toList(),
                  ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const Spacer(),
          ElevatedButton(
            onPressed: _isLoading ? null : _placeOrder,
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.orange),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Pay with Chapa',
                    style: TextStyle(fontSize: 16, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}
