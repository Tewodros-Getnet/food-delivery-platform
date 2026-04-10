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
}
