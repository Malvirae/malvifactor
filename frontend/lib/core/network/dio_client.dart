import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:malvifactor/core/config/server_config_provider.dart';

const String accessTokenStorageKey = 'malvifactor_access_token';
const String refreshTokenStorageKey = 'malvifactor_refresh_token';

class SessionExpiredNotifier extends StateNotifier<int> {
  SessionExpiredNotifier() : super(0);

  void notifyExpired() {
    state = state + 1;
  }
}

final sessionExpiredProvider =
    StateNotifierProvider<SessionExpiredNotifier, int>(
  (ref) => SessionExpiredNotifier(),
);

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.storage,
    required this.readBaseUrl,
    required this.onSessionExpired,
  });

  final Dio dio;
  final FlutterSecureStorage storage;
  final String Function() readBaseUrl;
  final void Function() onSessionExpired;

  Completer<bool>? _refreshCompleter;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.baseUrl = readBaseUrl();
    final skipAuth = options.extra['skipAuth'] == true;
    if (!skipAuth) {
      final token = await storage.read(key: accessTokenStorageKey);
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final options = err.requestOptions;
    final skipAuth = options.extra['skipAuth'] == true;
    final alreadyRetried = options.extra['retried'] == true;

    if (statusCode != 401 || skipAuth || alreadyRetried) {
      handler.next(err);
      return;
    }

    final refreshed = await _refreshTokens();
    if (!refreshed) {
      await storage.delete(key: accessTokenStorageKey);
      await storage.delete(key: refreshTokenStorageKey);
      onSessionExpired();
      handler.next(err);
      return;
    }

    final newAccessToken = await storage.read(key: accessTokenStorageKey);
    if (newAccessToken == null || newAccessToken.isEmpty) {
      handler.next(err);
      return;
    }

    final retryOptions = options.copyWith(
      baseUrl: readBaseUrl(),
      headers: {
        ...options.headers,
        'Authorization': 'Bearer $newAccessToken',
      },
      extra: {
        ...options.extra,
        'retried': true,
      },
    );

    try {
      final response = await dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }

  Future<bool> _refreshTokens() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      final refreshToken = await storage.read(key: refreshTokenStorageKey);
      if (refreshToken == null || refreshToken.isEmpty) {
        completer.complete(false);
        return false;
      }

      final refreshDio = Dio(
        BaseOptions(
          baseUrl: readBaseUrl(),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        ),
      );

      final response = await refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      final data = response.data;
      final newAccess = data?['access_token'] as String?;
      final newRefresh = data?['refresh_token'] as String?;
      if (newAccess == null || newRefresh == null) {
        completer.complete(false);
        return false;
      }

      await storage.write(key: accessTokenStorageKey, value: newAccess);
      await storage.write(key: refreshTokenStorageKey, value: newRefresh);
      completer.complete(true);
      return true;
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }
}

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: ref.read(serverConfigProvider),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      storage: storage,
      readBaseUrl: () => ref.read(serverConfigProvider),
      onSessionExpired: () =>
          ref.read(sessionExpiredProvider.notifier).notifyExpired(),
    ),
  );

  return dio;
});
