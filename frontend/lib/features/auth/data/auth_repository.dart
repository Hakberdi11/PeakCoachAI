import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'token_storage.dart';

class AuthRepository {
  AuthRepository(this._dio, this._tokenStorage);

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Future<void> register({required String email, required String password}) async {
    await _dio.post(
      '/api/auth/register/',
      data: {'email': email, 'password': password},
    );
  }

  Future<void> login({required String email, required String password}) async {
    final response = await _dio.post(
      '/api/auth/login/',
      data: {'email': email, 'password': password},
    );
    await _tokenStorage.saveTokens(
      access: response.data['access'] as String,
      refresh: response.data['refresh'] as String,
    );
  }

  Future<void> logout() => _tokenStorage.clear();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider), ref.watch(tokenStorageProvider));
});
