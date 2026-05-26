import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final secureStorageProvider = Provider<SecureStorageService>(
  (_) => SecureStorageService(),
);

class SecureStorageService {
  final _storage = const FlutterSecureStorage();
  Future<void> saveTokens({
    required String jwt,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: 'jwt', value: jwt),
      _storage.write(key: 'refreshToken', value: refreshToken),
    ]);
  }

  Future<String?> getJwt() => _storage.read(key: 'jwt');
  Future<String?> getRefreshToken() => _storage.read(key: 'refreshToken');
  Future<void> clearTokens() => _storage.deleteAll();

  // Rider availability persistence
  Future<void> saveAvailability(bool isAvailable) => _storage.write(
      key: 'rider_available', value: isAvailable ? 'true' : 'false');
  Future<bool> getAvailability() async {
    final val = await _storage.read(key: 'rider_available');
    return val == 'true';
  }

  // ── Active delivery state persistence ──────────────────────────────────────
  // Survives app restarts so the rider never loses navigation coordinates.

  Future<void> saveDeliveryState({
    required String orderId,
    required double restaurantLat,
    required double restaurantLon,
    required double customerLat,
    required double customerLon,
    required bool pickedUp,
  }) async {
    await Future.wait([
      _storage.write(key: 'delivery_order_id', value: orderId),
      _storage.write(key: 'delivery_restaurant_lat', value: restaurantLat.toString()),
      _storage.write(key: 'delivery_restaurant_lon', value: restaurantLon.toString()),
      _storage.write(key: 'delivery_customer_lat', value: customerLat.toString()),
      _storage.write(key: 'delivery_customer_lon', value: customerLon.toString()),
      _storage.write(key: 'delivery_picked_up', value: pickedUp ? 'true' : 'false'),
    ]);
  }

  Future<void> updateDeliveryPickedUp(bool pickedUp) =>
      _storage.write(key: 'delivery_picked_up', value: pickedUp ? 'true' : 'false');

  Future<Map<String, dynamic>?> getDeliveryState() async {
    final orderId = await _storage.read(key: 'delivery_order_id');
    if (orderId == null) return null;
    final rLat = double.tryParse(await _storage.read(key: 'delivery_restaurant_lat') ?? '');
    final rLon = double.tryParse(await _storage.read(key: 'delivery_restaurant_lon') ?? '');
    final cLat = double.tryParse(await _storage.read(key: 'delivery_customer_lat') ?? '');
    final cLon = double.tryParse(await _storage.read(key: 'delivery_customer_lon') ?? '');
    final pickedUp = (await _storage.read(key: 'delivery_picked_up')) == 'true';
    if (rLat == null || rLon == null || cLat == null || cLon == null) return null;
    return {
      'orderId': orderId,
      'restaurantLat': rLat,
      'restaurantLon': rLon,
      'customerLat': cLat,
      'customerLon': cLon,
      'pickedUp': pickedUp,
    };
  }

  Future<void> clearDeliveryState() async {
    await Future.wait([
      _storage.delete(key: 'delivery_order_id'),
      _storage.delete(key: 'delivery_restaurant_lat'),
      _storage.delete(key: 'delivery_restaurant_lon'),
      _storage.delete(key: 'delivery_customer_lat'),
      _storage.delete(key: 'delivery_customer_lon'),
      _storage.delete(key: 'delivery_picked_up'),
    ]);
  }
}
