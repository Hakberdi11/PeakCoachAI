import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/token_storage.dart';

enum AuthStatus { unauthenticated, authenticated }

class AuthState {
  const AuthState(this.status);

  final AuthStatus status;
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final token = await ref.watch(tokenStorageProvider).accessToken;
    return AuthState(
      token != null ? AuthStatus.authenticated : AuthStatus.unauthenticated,
    );
  }

  Future<void> refreshFromStorage() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final token = await ref.read(tokenStorageProvider).accessToken;
      return AuthState(
        token != null ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      );
    });
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AsyncData(AuthState(AuthStatus.unauthenticated));
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
