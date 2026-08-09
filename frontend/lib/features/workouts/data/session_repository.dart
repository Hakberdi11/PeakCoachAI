import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'session_models.dart';

class SessionRepository {
  SessionRepository(this._dio);

  final Dio _dio;

  Future<WorkoutSessionModel> startSession(int dayId) async {
    final response = await _dio.post(
      '/api/workouts/sessions/start/',
      data: {'workout_day': dayId},
    );
    return WorkoutSessionModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<WorkoutSessionModel> fetchSession(int sessionId) async {
    final response = await _dio.get('/api/workouts/sessions/$sessionId/');
    return WorkoutSessionModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<bool> logSet(
    int sessionId, {
    required int plannedExerciseId,
    required int setNumber,
    required double weight,
    required int reps,
  }) async {
    final response = await _dio.post(
      '/api/workouts/sessions/$sessionId/log-set/',
      data: {
        'planned_exercise': plannedExerciseId,
        'set_number': setNumber,
        'weight': weight,
        'reps': reps,
      },
    );
    return response.data['is_new_pr'] as bool;
  }

  Future<void> skipExercise(int sessionId, int plannedExerciseId) async {
    await _dio.post(
      '/api/workouts/sessions/$sessionId/skip-exercise/',
      data: {'planned_exercise': plannedExerciseId},
    );
  }

  Future<void> replaceExercise(
    int sessionId,
    int plannedExerciseId,
    String newExerciseName,
  ) async {
    await _dio.post(
      '/api/workouts/sessions/$sessionId/replace-exercise/',
      data: {'planned_exercise': plannedExerciseId, 'new_exercise_name': newExerciseName},
    );
  }

  Future<void> finishSession(int sessionId) async {
    await _dio.post('/api/workouts/sessions/$sessionId/finish/');
  }

  Future<void> submitFeedback(int sessionId, {required String difficulty, String notes = ''}) async {
    await _dio.post(
      '/api/workouts/sessions/$sessionId/feedback/',
      data: {'difficulty': difficulty, 'notes': notes},
    );
  }
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(ref.watch(dioProvider));
});

final sessionProvider = FutureProvider.family.autoDispose<WorkoutSessionModel, int>(
  (ref, sessionId) => ref.watch(sessionRepositoryProvider).fetchSession(sessionId),
);
