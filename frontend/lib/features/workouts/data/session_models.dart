import 'workout_models.dart';

class SetLogEntry {
  const SetLogEntry({
    required this.id,
    required this.setNumber,
    required this.weight,
    required this.reps,
  });

  final int id;
  final int setNumber;
  final double weight;
  final int reps;

  factory SetLogEntry.fromJson(Map<String, dynamic> json) => SetLogEntry(
    id: json['id'] as int,
    setNumber: json['set_number'] as int,
    weight: (json['weight'] as num).toDouble(),
    reps: json['reps'] as int,
  );
}

class ExerciseLogEntry {
  const ExerciseLogEntry({
    required this.id,
    required this.plannedExerciseId,
    required this.exerciseName,
    required this.replacedWithName,
    required this.status,
    required this.sets,
  });

  final int id;
  final int? plannedExerciseId;
  final String exerciseName;
  final String replacedWithName;
  final String status;
  final List<SetLogEntry> sets;

  String get displayName => replacedWithName.isNotEmpty ? replacedWithName : exerciseName;

  factory ExerciseLogEntry.fromJson(Map<String, dynamic> json) => ExerciseLogEntry(
    id: json['id'] as int,
    plannedExerciseId: json['planned_exercise_id'] as int?,
    exerciseName: json['exercise_name'] as String,
    replacedWithName: json['replaced_with_name'] as String? ?? '',
    status: json['status'] as String,
    sets: (json['sets'] as List)
        .map((s) => SetLogEntry.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

class WorkoutSessionModel {
  const WorkoutSessionModel({
    required this.id,
    required this.status,
    required this.workoutDay,
    required this.exerciseLogs,
  });

  final int id;
  final String status;
  final WorkoutDay? workoutDay;
  final List<ExerciseLogEntry> exerciseLogs;

  factory WorkoutSessionModel.fromJson(Map<String, dynamic> json) => WorkoutSessionModel(
    id: json['id'] as int,
    status: json['status'] as String,
    workoutDay: json['workout_day'] != null
        ? WorkoutDay.fromJson(json['workout_day'] as Map<String, dynamic>)
        : null,
    exerciseLogs: (json['exercise_logs'] as List)
        .map((e) => ExerciseLogEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  ExerciseLogEntry? logFor(int plannedExerciseId) {
    for (final log in exerciseLogs) {
      if (log.plannedExerciseId == plannedExerciseId) return log;
    }
    return null;
  }
}
