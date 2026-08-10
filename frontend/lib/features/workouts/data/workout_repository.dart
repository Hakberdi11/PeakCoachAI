import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../onboarding/state/onboarding_draft.dart';
import 'workout_models.dart';

class PlanRevision {
  const PlanRevision({required this.plan, required this.changeSummary});

  final WorkoutPlan plan;
  final String changeSummary;
}

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

  /// Tells the AI to revise the active plan per a free-text instruction. The
  /// instruction is remembered by the backend and honored on future
  /// generations/revisions too, so it only needs to be said once.
  Future<PlanRevision> revisePlan(String instruction) async {
    final response = await _dio.post(
      '/api/workouts/plans/revise/',
      data: {'instruction': instruction},
    );
    final data = response.data as Map<String, dynamic>;
    return PlanRevision(
      plan: WorkoutPlan.fromJson(data),
      changeSummary: data['change_summary'] as String? ?? '',
    );
  }

  Future<List<ExerciseCatalogEntry>> fetchExerciseCatalog({String? muscleGroup}) async {
    final response = await _dio.get(
      '/api/workouts/exercises/',
      queryParameters: muscleGroup != null ? {'muscle_group': muscleGroup} : null,
    );
    return (response.data as List)
        .map((e) => ExerciseCatalogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addExercise(
    int dayId, {
    required String exerciseName,
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required int restSeconds,
  }) async {
    await _dio.post(
      '/api/workouts/plans/active/days/$dayId/exercises/',
      data: {
        'exercise_name': exerciseName,
        'target_sets': targetSets,
        'target_reps_min': targetRepsMin,
        'target_reps_max': targetRepsMax,
        'rest_seconds': restSeconds,
      },
    );
  }

  Future<void> updateExercise(int exerciseId, Map<String, dynamic> fields) async {
    await _dio.patch('/api/workouts/plans/active/exercises/$exerciseId/', data: fields);
  }

  Future<void> removeExercise(int exerciseId) async {
    await _dio.delete('/api/workouts/plans/active/exercises/$exerciseId/');
  }

  Future<void> reorderExercises(int dayId, List<int> exerciseIds) async {
    await _dio.post(
      '/api/workouts/plans/active/days/$dayId/exercises/reorder/',
      data: {'exercise_ids': exerciseIds},
    );
  }
}

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(ref.watch(dioProvider));
});

final activePlanProvider = FutureProvider.autoDispose<WorkoutPlan?>((ref) {
  return ref.watch(workoutRepositoryProvider).fetchActivePlan();
});
