import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/constants/api_constants.dart';
import '../models/user_model.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) =>
      AuthService(ref.read(dioClientProvider), ref.read(secureStorageProvider)),
);

class AuthService {
  final DioClient _client;
  final SecureStorageService _storage;
  AuthService(this._client, this._storage);

  Future<UserModel> register({
    required String email,
    required String password,
  }) async {
    final res = await _client.dio.post(
      ApiConstants.register,
      data: {'email': email, 'password': password, 'role': 'rider'},
    );
    final data = res.data['data'] as Map<String, dynamic>;
    await _storage.saveTokens(
      jwt: data['tokens']['jwt'] as String,
      refreshToken: data['tokens']['refreshToken'] as String,
    );
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final res = await _client.dio.post(
      ApiConstants.login,
      data: {'email': email, 'password': password},
    );
    final data = res.data['data'] as Map<String, dynamic>;
    await _storage.saveTokens(
      jwt: data['tokens']['jwt'] as String,
      refreshToken: data['tokens']['refreshToken'] as String,
    );
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final rt = await _storage.getRefreshToken();
    if (rt != null) {
      try {
        await _client.dio.post(ApiConstants.logout, data: {'refreshToken': rt});
      } catch (_) {}
    }
    await _storage.clearTokens();
  }

  Future<bool> isLoggedIn() async => (await _storage.getJwt()) != null;
}
