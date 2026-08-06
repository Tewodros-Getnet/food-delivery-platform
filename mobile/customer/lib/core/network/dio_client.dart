import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api_constants.dart';

final dioClientProvider = Provider<DioClient>((ref) => DioClient());

// Emits whenever the refresh token is rejected — use ref.listen on this
// in the app root to force logout and redirect to login.
final sessionExpiredProvider = StreamProvider<void>(
  (ref) => ref.read(dioClientProvider).sessionExpired,
);

class DioClient {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  // Fires once when the refresh token is rejected by the server.
  // Listeners should log the user out and redirect to login.
  final _sessionExpiredController = StreamController<void>.broadcast();
  Stream<void> get sessionExpired => _sessionExpiredController.stream;

  DioClient() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 120),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'jwt');
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final rt = await _storage.read(key: 'refreshToken');
          if (rt != null) {
            try {
              final res = await Dio().post(
                  '${ApiConstants.baseUrl}${ApiConstants.refresh}',
                  data: {'refreshToken': rt});
              final data = res.data['data'] as Map<String, dynamic>;
              final newJwt = data['jwt'] as String;
              final newRt = data['refreshToken'] as String;
              await _storage.write(key: 'jwt', value: newJwt);
              await _storage.write(key: 'refreshToken', value: newRt);
              error.requestOptions.headers['Authorization'] = 'Bearer $newJwt';
              return handler.resolve(await _dio.fetch(error.requestOptions));
            } on DioException catch (e) {
              if (e.response?.statusCode == 401) {
                // Refresh token rejected — wipe tokens and notify listeners
                await _storage.deleteAll();
                _sessionExpiredController.add(null);
              }
              // Network/timeout errors: don't log out, just pass through
            } catch (_) {
              // JSON parse or unexpected error — don't wipe tokens
            }
          } else {
            // No refresh token at all — session is gone
            await _storage.deleteAll();
            _sessionExpiredController.add(null);
          }
        }
        handler.next(error);
      },
    ));
  }

  Dio get dio => _dio;

  void dispose() {
    _sessionExpiredController.close();
  }
}
