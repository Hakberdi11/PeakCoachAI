import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'progress_models.dart';

class ProgressRepository {
  ProgressRepository(this._dio);

  final Dio _dio;

  Future<ProgressSummary> fetchSummary() async {
    final response = await _dio.get('/api/progress/summary/');
    return ProgressSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<SessionVolumePoint>> fetchHistory() async {
    final response = await _dio.get('/api/progress/history/');
    return (response.data as List)
        .map((e) => SessionVolumePoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository(ref.watch(dioProvider));
});

final progressSummaryProvider = FutureProvider.autoDispose<ProgressSummary>((ref) {
  return ref.watch(progressRepositoryProvider).fetchSummary();
});

final progressHistoryProvider = FutureProvider.autoDispose<List<SessionVolumePoint>>((ref) {
  return ref.watch(progressRepositoryProvider).fetchHistory();
});
