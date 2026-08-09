import 'package:dio/dio.dart';

String extractAuthError(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic>) {
    final firstValue = data.values.firstOrNull;
    if (firstValue is List && firstValue.isNotEmpty) {
      return firstValue.first.toString();
    }
    if (firstValue is String) {
      return firstValue;
    }
  }
  return 'Something went wrong. Please try again.';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
