import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/cart_provider.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    if (cart.items.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: const Text('Cart')),
          body: const Center(child: Text('Your cart is empty')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: Column(children: [
        Expanded(
            child: ListView.builder(
          itemCount: cart.items.length,
          itemBuilder: (ctx, i) {
            final item = cart.items[i];
            return ListTile(
              title: Text(item.menuItem.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ETB ${item.unitPrice.toStringAsFixed(2)}'),
                  if (item.selectedModifiers.isNotEmpty)
                    Text(
                      item.selectedModifiers
                          .map((m) =>
                              '${m.option}${m.price > 0 ? ' +ETB${m.price.toStringAsFixed(0)}' : ''}')
                          .join(', '),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                ],
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(item.cartKey, item.quantity - 1)),
                Text('${item.quantity}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(item.cartKey, item.quantity + 1)),
              ]),
            );
          },
        )),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Subtotal', style: TextStyle(fontSize: 16)),
              Text('ETB ${cart.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.push('/checkout'),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.orange),
                  child: const Text('Proceed to Checkout',
                      style: TextStyle(fontSize: 16, color: Colors.white)),
                )),
          ]),
        ),
      ]),
    );
  }
}
