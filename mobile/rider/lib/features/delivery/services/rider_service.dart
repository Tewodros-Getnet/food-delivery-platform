import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_constants.dart';

final riderServiceProvider = Provider<RiderService>(
  (ref) => RiderService(ref.read(dioClientProvider)),
);

class RiderService {
  final DioClient _client;
  RiderService(this._client);

  Future<void> updateLocation(
    double lat,
    double lon,
    String availability,
  ) async {
    await _client.dio.put(
      ApiConstants.ridersLocation,
      data: {'latitude': lat, 'longitude': lon, 'availability': availability},
    );
  }

  Future<void> setAvailability(String availability) async {
    await _client.dio.put(
      ApiConstants.ridersAvailability,
      data: {'availability': availability},
    );
  }

  Future<Map<String, dynamic>?> acceptDelivery(String orderId) async {
    final res =
        await _client.dio.post('${ApiConstants.deliveries}/$orderId/accept');
    return res.data['data'] as Map<String, dynamic>?;
  }

  Future<void> declineDelivery(String orderId) async {
    await _client.dio.post('${ApiConstants.deliveries}/$orderId/decline');
  }

  Future<void> confirmPickup(String orderId) async {
    await _client.dio.put('${ApiConstants.deliveries}/$orderId/pickup');
  }

  Future<void> confirmDelivery(String orderId) async {
    await _client.dio.put('${ApiConstants.deliveries}/$orderId/deliver');
  }

  Future<String?> refreshToken(String refreshToken) async {
    try {
      final res = await _client.dio
          .post(ApiConstants.refresh, data: {'refreshToken': refreshToken});
      return res.data['data']['jwt'] as String?;
    } catch (_) {
      return null;
    }
  }
}
