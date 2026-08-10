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

  final _sessionExpiredController = StreamController<void>.broadcast();
  Stream<void> get sessionExpired => _sessionExpiredController.stream;

  // ── Refresh mutex ─────────────────────────────────────────────────────────
  bool _refreshing = false;
  final List<Completer<String?>> _refreshQueue = [];

  Future<String?> _refreshOnce() async {
    if (_refreshing) {
      final completer = Completer<String?>();
      _refreshQueue.add(completer);
      return completer.future;
    }

    _refreshing = true;
    String? newJwt;

    try {
      final rt = await _storage.read(key: 'refreshToken');
      if (rt == null) {
        await _storage.deleteAll();
        _sessionExpiredController.add(null);
        return null;
      }

      final res = await Dio().post(
        '${ApiConstants.baseUrl}${ApiConstants.refresh}',
        data: {'refreshToken': rt},
      );
      final data = res.data['data'] as Map<String, dynamic>;
      newJwt = data['jwt'] as String;
      final newRt = data['refreshToken'] as String;
      await _storage.write(key: 'jwt', value: newJwt);
      await _storage.write(key: 'refreshToken', value: newRt);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _storage.deleteAll();
        _sessionExpiredController.add(null);
      }
      newJwt = null;
    } catch (_) {
      newJwt = null;
    } finally {
      _refreshing = false;
      for (final c in _refreshQueue) {
        c.complete(newJwt);
      }
      _refreshQueue.clear();
    }

    return newJwt;
  }

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
          final newJwt = await _refreshOnce();
          if (newJwt != null) {
            error.requestOptions.headers['Authorization'] = 'Bearer $newJwt';
            try {
              return handler.resolve(await _dio.fetch(error.requestOptions));
            } catch (_) {}
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
