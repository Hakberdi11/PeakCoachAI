class PlannedExercise {
  const PlannedExercise({
    this.id,
    required this.order,
    required this.name,
    required this.targetSets,
    required this.targetRepsMin,
    required this.targetRepsMax,
    required this.restSeconds,
  });

  final int? id;
  final int order;
  final String name;
  final int targetSets;
  final int targetRepsMin;
  final int targetRepsMax;
  final int restSeconds;

  factory PlannedExercise.fromJson(Map<String, dynamic> json) => PlannedExercise(
    id: json['id'] as int?,
    order: json['order'] as int,
    name: json['exercise_name'] as String,
    targetSets: json['target_sets'] as int,
    targetRepsMin: json['target_reps_min'] as int,
    targetRepsMax: json['target_reps_max'] as int,
    restSeconds: json['rest_seconds'] as int? ?? 90,
  );
}

class WorkoutDay {
  const WorkoutDay({this.id, required this.name, required this.exercises});

  final int? id;
  final String name;
  final List<PlannedExercise> exercises;

  factory WorkoutDay.fromJson(Map<String, dynamic> json) => WorkoutDay(
    id: json['id'] as int?,
    name: json['name'] as String,
    exercises: (json['exercises'] as List)
        .map((e) => PlannedExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// Represents both a persisted plan (has [id]/[createdAt]) and an anonymous
/// pre-signup preview (does not) — the preview endpoint returns only `days`.
class WorkoutPlan {
  const WorkoutPlan({this.id, this.createdAt, this.isActive = false, required this.days});

  final int? id;
  final DateTime? createdAt;
  final bool isActive;
  final List<WorkoutDay> days;

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
    id: json['id'] as int?,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
    isActive: json['is_active'] as bool? ?? false,
    days: (json['days'] as List)
        .map((d) => WorkoutDay.fromJson(d as Map<String, dynamic>))
        .toList(),
  );
}
