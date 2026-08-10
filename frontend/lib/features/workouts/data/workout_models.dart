class PlannedExercise {
  const PlannedExercise({
    this.id,
    required this.order,
    required this.name,
    required this.targetSets,
    required this.targetRepsMin,
    required this.targetRepsMax,
    required this.restSeconds,
    this.targetRir,
  });

  final int? id;
  final int order;
  final String name;
  final int targetSets;
  final int targetRepsMin;
  final int targetRepsMax;
  final int restSeconds;
  final int? targetRir;

  factory PlannedExercise.fromJson(Map<String, dynamic> json) => PlannedExercise(
    id: json['id'] as int?,
    order: json['order'] as int,
    name: json['exercise_name'] as String,
    targetSets: json['target_sets'] as int,
    targetRepsMin: json['target_reps_min'] as int,
    targetRepsMax: json['target_reps_max'] as int,
    restSeconds: json['rest_seconds'] as int? ?? 90,
    targetRir: json['target_rir'] as int?,
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

/// An entry from the curated exercise catalog, used by the manual "add
/// exercise" picker — distinct from [PlannedExercise], which is a freeform
/// AI- or user-authored name inside a plan.
class ExerciseCatalogEntry {
  const ExerciseCatalogEntry({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.equipmentNeeded,
  });

  final int id;
  final String name;
  final String muscleGroup;
  final List<String> equipmentNeeded;

  factory ExerciseCatalogEntry.fromJson(Map<String, dynamic> json) => ExerciseCatalogEntry(
    id: json['id'] as int,
    name: json['name'] as String,
    muscleGroup: json['muscle_group'] as String,
    equipmentNeeded: (json['equipment_needed'] as List).cast<String>(),
  );
}
