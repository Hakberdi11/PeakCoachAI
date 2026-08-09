import 'package:dio/dio.dart';

import '../../features/auth/data/token_storage.dart';

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this._tokenStorage,
    required this._refreshDio,
    required this._onSessionExpired,
  });

  final TokenStorage _tokenStorage;
  final Dio _refreshDio;
  final void Function() _onSessionExpired;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStorage.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final isUnauthorized = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra['retried'] == true;

    if (!isUnauthorized || alreadyRetried) {
      handler.next(err);
      return;
    }

    final refreshToken = await _tokenStorage.refreshToken;
    if (refreshToken == null) {
      await _tokenStorage.clear();
      _onSessionExpired();
      handler.next(err);
      return;
    }

    try {
      final response = await _refreshDio.post(
        '/api/auth/refresh/',
        data: {'refresh': refreshToken},
      );
      final newAccess = response.data['access'] as String;
      await _tokenStorage.saveAccessToken(newAccess);

      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccess';
      retryOptions.extra = {...retryOptions.extra, 'retried': true};

      final retryResponse = await _refreshDio.fetch(retryOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      await _tokenStorage.clear();
      _onSessionExpired();
      handler.next(err);
    }
  }
}
