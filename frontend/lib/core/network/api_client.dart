import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/token_storage.dart';
import '../../features/auth/state/auth_provider.dart';
import '../config/app_config.dart';
import 'auth_interceptor.dart';

final _refreshDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      tokenStorage: ref.watch(tokenStorageProvider),
      refreshDio: ref.watch(_refreshDioProvider),
      onSessionExpired: () => ref.read(authProvider.notifier).logout(),
    ),
  );

  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  return dio;
});
