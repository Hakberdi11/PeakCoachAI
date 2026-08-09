import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the raw preview-plan response (display shape, no id/created_at) so
/// it can be shown pre-signup and later persisted verbatim via save-preview
/// without a second AI call.
final planPreviewProvider = StateProvider<Map<String, dynamic>?>((ref) => null);
