import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../cart/providers/cart_provider.dart';
import '../services/order_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';
import '../../../l10n/app_localizations.dart';

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
  double? _estimatedFee;
  bool _estimatingFee = false;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _awaitingReturn &&
        _pendingOrderId != null) {
      _awaitingReturn = false;
      _verifyAndNavigate(_pendingOrderId!);
    }
  }

  Future<void> _estimateDeliveryFee(String addressId) async {
    final cart = ref.read(cartProvider);
    if (cart.restaurantId == null) return;
    setState(() { _estimatingFee = true; _estimatedFee = null; });
    try {
      final res = await ref.read(dioClientProvider).dio.get(
        ApiConstants.estimateFee,
        queryParameters: {
          'restaurant_id': cart.restaurantId,
          'delivery_address_id': addressId,
        },
      );
      final fee = double.tryParse((res.data['data']['fee'] ?? 0).toString());
      if (mounted) setState(() => _estimatedFee = fee);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _estimatingFee = false);
    }
  }

  Future<void> _verifyAndNavigate(String orderId) async {
    final l10n = AppLocalizations.of(context);
    setState(() { _isLoading = true; _error = null; });
    try {
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 1500));
        final order = await ref.read(orderServiceProvider).getById(orderId);
        if (order.status == 'pending_acceptance' || order.status == 'confirmed') {
          ref.read(cartProvider.notifier).clear();
          if (mounted) context.push('/order/$orderId/track');
          return;
        }
        if (order.status == 'payment_failed') {
          setState(() => _error = l10n.paymentFailedRetry);
          return;
        }
      }
      if (mounted) context.push('/order/$orderId/track');
    } catch (e) {
      if (mounted) context.push('/order/$orderId/track');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _placeOrder() async {
    final l10n = AppLocalizations.of(context);
    final cart = ref.read(cartProvider);
    if (cart.restaurantId == null || cart.items.isEmpty) return;
    if (_selectedAddressId == null) {
      setState(() => _error = l10n.selectDeliveryAddress);
      return;
    }
    setState(() { _isLoading = true; _error = null; });
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
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && mounted) {
          setState(() => _error = l10n.couldNotOpenPayment);
          return;
        }
        setState(() {
          _pendingOrderId = orderId;
          _awaitingReturn = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (!_awaitingReturn) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    final addressesAsync = ref.watch(_addressesProvider);
    final subtotal = cart.subtotal;
    final total = subtotal + (_estimatedFee ?? 0);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkout)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Order summary ──────────────────────────────────────────────
            _SectionHeader(title: l10n.orderSummary),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  ...cart.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${item.menuItem.name} × ${item.quantity}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                  if (item.selectedModifiers.isNotEmpty)
                                    Text(
                                      item.selectedModifiers
                                          .map((m) => m.option).join(', '),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.45)),
                                    ),
                                ],
                              ),
                            ),
                            Text('ETB ${item.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.subtotal,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        Text('ETB ${subtotal.toStringAsFixed(2)}'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.deliveryFee,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        _estimatingFee
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Text(
                                _estimatedFee != null
                                    ? 'ETB ${_estimatedFee!.toStringAsFixed(2)}'
                                    : '—',
                                style: TextStyle(
                                    color: _estimatedFee != null
                                        ? Theme.of(context).colorScheme.onSurface
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.38)),
                              ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.total,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(
                          _estimatedFee != null
                              ? 'ETB ${total.toStringAsFixed(2)}'
                              : 'ETB ${subtotal.toStringAsFixed(2)}+',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Delivery address ───────────────────────────────────────────
            _SectionHeader(title: l10n.deliveryAddress),
            const SizedBox(height: 10),
            addressesAsync.when(
              loading: () => const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator())),
              error: (e, _) => Text('${l10n.failedToLoadAddresses}: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (addresses) => addresses.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.noSavedAddresses,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => context.push('/addresses'),
                            child: Text(l10n.addDeliveryAddress,
                                style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: addresses.map((a) {
                        final isSelected =
                            _selectedAddressId == a['id'] as String;
                        return GestureDetector(
                          onTap: () {
                            final id = a['id'] as String;
                            setState(() => _selectedAddressId = id);
                            _estimateDeliveryFee(id);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color:
                                    isSelected ? Colors.orange : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if ((a['label'] as String?)
                                            ?.isNotEmpty ==
                                        true)
                                      Text(a['label'] as String,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                    Text(
                                      a['address_line'] as String,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
            ),

            const SizedBox(height: 24),

            // ── Awaiting payment return ────────────────────────────────────
            if (_awaitingReturn) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimaryContainer)),
                    const SizedBox(width: 12),
                    Text(l10n.waitingPayment,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Error ──────────────────────────────────────────────────────
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer)),
                    if (_pendingOrderId != null)
                      TextButton(
                        onPressed: () => _verifyAndNavigate(_pendingOrderId!),
                        child: Text(l10n.checkPaymentStatus),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Pay button ─────────────────────────────────────────────────
            if (!_awaitingReturn)
              ElevatedButton(
                onPressed: _isLoading ? null : _placeOrder,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  disabledBackgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                  disabledForegroundColor:
                      Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text(
                        _estimatedFee != null
                            ? l10n.payWithChapaAmount(
                                total.toStringAsFixed(2))
                            : l10n.payWithChapa,
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
  }
}
