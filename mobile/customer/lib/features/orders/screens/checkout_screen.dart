import 'dart:async';
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

class _CheckoutScreenState extends ConsumerState<CheckoutScreen>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  String? _error;
  String? _selectedAddressId;

  // Tracks the pending order while user is on Chapa page
  String? _pendingOrderId;
  bool _awaitingReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Called when app comes back to foreground after user returns from Chapa
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _awaitingReturn &&
        _pendingOrderId != null) {
      _awaitingReturn = false;
      _verifyAndNavigate(_pendingOrderId!);
    }
  }

  // Bug 4 fix: poll order status after returning from Chapa browser
  Future<void> _verifyAndNavigate(String orderId) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Poll up to 5 times with 1.5s delay to give webhook time to fire
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 1500));
        final order = await ref.read(orderServiceProvider).getById(orderId);
        if (order.status == 'confirmed') {
          if (mounted) context.push('/order/$orderId/track');
          return;
        }
        if (order.status == 'payment_failed') {
          setState(() => _error =
              'Payment failed. Please try again or use a different method.');
          return;
        }
      }
      // Webhook may still be in flight — navigate anyway, tracking screen will update
      if (mounted) context.push('/order/$orderId/track');
    } catch (e) {
      if (mounted) context.push('/order/$orderId/track');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
        // Bug 4 fix: mark that we're waiting for the user to return from Chapa
        ref.read(cartProvider.notifier).clear();
        setState(() {
          _pendingOrderId = orderId;
          _awaitingReturn = true;
          _isLoading = false;
        });
        // didChangeAppLifecycleState will handle navigation on return
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (!_awaitingReturn) setState(() => _isLoading = false);
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
          if (_awaitingReturn) ...[
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 12),
                Text('Waiting for payment confirmation...'),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_pendingOrderId != null)
              TextButton(
                onPressed: () => _verifyAndNavigate(_pendingOrderId!),
                child: const Text('Check payment status'),
              ),
          ],
          const Spacer(),
          if (!_awaitingReturn)
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
