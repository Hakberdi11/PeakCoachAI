import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../state/onboarding_draft.dart';

class OnboardingRepository {
  OnboardingRepository(this._dio);

  final Dio _dio;

  Future<bool> isComplete() async {
    try {
      await _dio.get('/api/onboarding/');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return false;
      rethrow;
    }
  }

  Future<void> submit(OnboardingDraft draft) async {
    await _dio.post('/api/onboarding/', data: draft.toJson());
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    try {
      final response = await _dio.get('/api/onboarding/');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.watch(dioProvider));
});

final onboardingProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) {
  return ref.watch(onboardingRepositoryProvider).fetchProfile();
});
