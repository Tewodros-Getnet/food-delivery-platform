import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../services/socket_service.dart';

class RiderLocation {
  final double latitude;
  final double longitude;
  const RiderLocation(this.latitude, this.longitude);
}

class OrderTrackingState {
  final OrderModel? order;
  final RiderLocation? riderLocation;
  final bool isLoading;
  final String? error;

  const OrderTrackingState({
    this.order,
    this.riderLocation,
    this.isLoading = false,
    this.error,
  });

  OrderTrackingState copyWith({
    OrderModel? order,
    RiderLocation? riderLocation,
    bool? isLoading,
    String? error,
  }) =>
      OrderTrackingState(
        order: order ?? this.order,
        riderLocation: riderLocation ?? this.riderLocation,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class OrderTrackingNotifier extends StateNotifier<OrderTrackingState> {
  final OrderService _orderService;
  final SocketService _socketService;

  OrderTrackingNotifier(this._orderService, this._socketService)
      : super(const OrderTrackingState());

  Future<void> trackOrder(String orderId) async {
    state = state.copyWith(isLoading: true);
    try {
      final order = await _orderService.getById(orderId);
      state = state.copyWith(order: order, isLoading: false);
      _listenToSocket(orderId);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _listenToSocket(String orderId) {
    _socketService.on('order:status_changed', (data) {
      final d = data['data'] as Map<String, dynamic>;
      if (d['orderId'] == orderId) {
        final updated = OrderModel.fromJson(d['order'] as Map<String, dynamic>);
        state = state.copyWith(order: updated);
      }
    });

    _socketService.on('rider:location_update', (data) {
      final d = data['data'] as Map<String, dynamic>;
      if (d['orderId'] == orderId) {
        state = state.copyWith(
          riderLocation: RiderLocation(
            (d['latitude'] as num).toDouble(),
            (d['longitude'] as num).toDouble(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _socketService.off('order:status_changed');
    _socketService.off('rider:location_update');
    super.dispose();
  }
}

final orderTrackingProvider = StateNotifierProvider.family<
    OrderTrackingNotifier, OrderTrackingState, String>((ref, orderId) {
  final notifier = OrderTrackingNotifier(
    ref.read(orderServiceProvider),
    ref.read(socketServiceProvider),
  );
  notifier.trackOrder(orderId);
  return notifier;
});

final orderListProvider = FutureProvider<List<OrderModel>>(
  (ref) => ref.read(orderServiceProvider).getOrders(),
);
