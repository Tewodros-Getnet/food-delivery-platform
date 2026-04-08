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
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
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
              final newJwt = res.data['data']['jwt'] as String;
              await _storage.write(key: 'jwt', value: newJwt);
              error.requestOptions.headers['Authorization'] = 'Bearer $newJwt';
              return handler.resolve(await _dio.fetch(error.requestOptions));
            } catch (_) {
              await _storage.deleteAll();
            }
          }
        }
        handler.next(error);
      },
    ));
  }

  Dio get dio => _dio;
}
