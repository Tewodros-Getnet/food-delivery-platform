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

  Future<String> register({
    required String email,
    required String password,
  }) async {
    final res = await _client.dio.post(
      ApiConstants.register,
      data: {'email': email, 'password': password, 'role': 'rider'},
    );
    final data = res.data['data'] as Map<String, dynamic>;
    return data['userId'] as String;
  }

  Future<UserModel> verifyOtp({
    required String userId,
    required String code,
  }) async {
    final res = await _client.dio.post(
      ApiConstants.verifyOtp,
      data: {'userId': userId, 'code': code},
    );
    final data = res.data['data'] as Map<String, dynamic>;
    await _storage.saveTokens(
      jwt: data['tokens']['jwt'] as String,
      refreshToken: data['tokens']['refreshToken'] as String,
    );
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> resendOtp({required String userId}) async {
    await _client.dio.post(ApiConstants.resendOtp, data: {'userId': userId});
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
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    if (user.role != 'rider') {
      throw Exception(
        'This account is not a rider account. '
        'Please use the correct app for your account type.',
      );
    }
    await _storage.saveTokens(
      jwt: data['tokens']['jwt'] as String,
      refreshToken: data['tokens']['refreshToken'] as String,
    );
    return user;
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
