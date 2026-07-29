import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/cart_provider.dart';
import '../models/cart_item.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    if (cart.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shopping_cart_outlined,
                  size: 72, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text('Your cart is empty',
                  style: TextStyle(fontSize: 17, color: Colors.grey)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Browse restaurants'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cart'),
        actions: [
          TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear Cart'),
                  content: const Text('Remove all items from your cart?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () {
                          ref.read(cartProvider.notifier).clear();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Clear',
                            style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            itemCount: cart.items.length,
            itemBuilder: (ctx, i) {
              final item = cart.items[i];
              return _CartItemTile(item: item);
            },
          ),
        ),
        _CartSummary(cart: cart),
      ]),
    );
  }
}

// ── Individual cart item tile with swipe-to-delete ────────────────────────────

class _CartItemTile extends ConsumerWidget {
  final CartItem item;
  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(item.cartKey),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade50,
        child: const Icon(Icons.delete_outline, color: Colors.red, size: 26),
      ),
      onDismissed: (_) =>
          ref.read(cartProvider.notifier).updateQuantity(item.cartKey, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          // Item image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: item.menuItem.imageUrl,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 64,
                height: 64,
                color: Colors.grey[200],
                child: const Icon(Icons.fastfood, color: Colors.grey, size: 28),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + modifiers + price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.menuItem.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (item.selectedModifiers.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.selectedModifiers.map((m) => m.option).join(', '),
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'ETB ${item.unitPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          // Quantity stepper
          Row(mainAxisSize: MainAxisSize.min, children: [
            _StepperButton(
              icon: Icons.remove,
              onTap: () => ref
                  .read(cartProvider.notifier)
                  .updateQuantity(item.cartKey, item.quantity - 1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('${item.quantity}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            _StepperButton(
              icon: Icons.add,
              onTap: () => ref
                  .read(cartProvider.notifier)
                  .updateQuantity(item.cartKey, item.quantity + 1),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Icon(icon, size: 16, color: Colors.orange),
      ),
    );
  }
}

// ── Cart summary + checkout button ────────────────────────────────────────────

class _CartSummary extends StatelessWidget {
  final CartState cart;
  const _CartSummary({required this.cart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, -3))
        ],
      ),
      child: Column(children: [
        // Subtotal row
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Subtotal (${cart.totalItems} items)',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text('ETB ${cart.subtotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13)),
        ]),
        const SizedBox(height: 4),
        // Delivery fee note
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Delivery fee',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text('Calculated at checkout',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ]),
        const Divider(height: 16),
        // Total
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text('ETB ${cart.subtotal.toStringAsFixed(2)}+',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.orange)),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.push('/checkout'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Proceed to Checkout',
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}
