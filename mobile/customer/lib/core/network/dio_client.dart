import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api_constants.dart';

final dioClientProvider = Provider<DioClient>((ref) => DioClient());

class DioClient {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

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
              // Only wipe tokens if the server explicitly rejected the refresh
              // (401 response). A timeout or network error should NOT log the
              // user out — they just need to retry when connectivity returns.
              if (e.response?.statusCode == 401) {
                await _storage.deleteAll();
              }
            } catch (_) {
              // Non-Dio error (e.g. JSON parse) — don't wipe tokens
            }
          }
        }
        handler.next(error);
      },
    ));
  }

  Dio get dio => _dio;
}
