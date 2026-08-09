import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class InsightEntry {
  const InsightEntry({required this.text, required this.category});

  final String text;
  final String category;

  factory InsightEntry.fromJson(Map<String, dynamic> json) =>
      InsightEntry(text: json['text'] as String, category: json['category'] as String);
}

class InsightsRepository {
  InsightsRepository(this._dio);

  final Dio _dio;

  Future<List<InsightEntry>> fetchLatest() async {
    final response = await _dio.get('/api/insights/latest/');
    return (response.data as List)
        .map((e) => InsightEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final insightsRepositoryProvider = Provider<InsightsRepository>((ref) {
  return InsightsRepository(ref.watch(dioProvider));
});

final latestInsightsProvider = FutureProvider.autoDispose<List<InsightEntry>>((ref) {
  return ref.watch(insightsRepositoryProvider).fetchLatest();
});
