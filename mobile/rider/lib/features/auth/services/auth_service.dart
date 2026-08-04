import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/constants/api_constants.dart';
import '../models/user_model.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) =>
      AuthService(ref.read(dioClientProvider), ref.read(secureStorageProvider)),
);

/// Extracts a human-readable message from any error.
/// DioException → reads server's JSON `message` field if available.
/// Everything else → falls back to e.toString().
String _parseError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Please check your internet connection.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
  return e.toString().replaceFirst('Exception: ', '');
}

class AuthService {
  final DioClient _client;
  final SecureStorageService _storage;
  AuthService(this._client, this._storage);

  Future<({String userId, String? devOtp})> register({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.dio.post(
        ApiConstants.register,
        data: {'email': email, 'password': password, 'role': 'rider'},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      return (
        userId: data['userId'] as String,
        devOtp: data['devOtp'] as String?,
      );
    } catch (e) {
      throw Exception(_parseError(e));
    }
  }

  Future<UserModel> verifyOtp({
    required String userId,
    required String code,
  }) async {
    try {
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
    } catch (e) {
      throw Exception(_parseError(e));
    }
  }

  Future<void> resendOtp({required String userId}) async {
    try {
      await _client.dio.post(ApiConstants.resendOtp, data: {'userId': userId});
    } catch (e) {
      throw Exception(_parseError(e));
    }
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    try {
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
    } catch (e) {
      if (e is Exception && e.toString().contains('correct app')) rethrow;
      throw Exception(_parseError(e));
    }
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
