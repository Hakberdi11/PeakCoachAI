import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../onboarding/state/onboarding_draft.dart';
import 'workout_models.dart';

class WorkoutRepository {
  WorkoutRepository(this._dio);

  final Dio _dio;

  /// Anonymous: generates a plan from onboarding answers without persisting it.
  Future<Map<String, dynamic>> previewPlan(OnboardingDraft draft) async {
    final response = await _dio.post(
      '/api/workouts/plans/preview/',
      data: draft.toJson(),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Persists a plan the user already saw via [previewPlan], without a second AI call.
  Future<WorkoutPlan> savePreview(Map<String, dynamic> previewPlan) async {
    final response = await _dio.post(
      '/api/workouts/plans/save-preview/',
      data: previewPlan,
    );
    return WorkoutPlan.fromJson(response.data as Map<String, dynamic>);
  }

  Future<WorkoutPlan> generatePlan() async {
    final response = await _dio.post('/api/workouts/plans/generate/');
    return WorkoutPlan.fromJson(response.data as Map<String, dynamic>);
  }

  Future<WorkoutPlan?> fetchActivePlan() async {
    try {
      final response = await _dio.get('/api/workouts/plans/active/');
      return WorkoutPlan.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(ref.watch(dioProvider));
});

final activePlanProvider = FutureProvider.autoDispose<WorkoutPlan?>((ref) {
  return ref.watch(workoutRepositoryProvider).fetchActivePlan();
});
