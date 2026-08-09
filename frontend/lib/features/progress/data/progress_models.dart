class PersonalRecordEntry {
  const PersonalRecordEntry({
    required this.exerciseName,
    required this.weight,
    required this.reps,
    required this.achievedAt,
  });

  final String exerciseName;
  final double weight;
  final int reps;
  final DateTime achievedAt;

  factory PersonalRecordEntry.fromJson(Map<String, dynamic> json) => PersonalRecordEntry(
    exerciseName: json['exercise_name'] as String,
    weight: (json['weight'] as num).toDouble(),
    reps: json['reps'] as int,
    achievedAt: DateTime.parse(json['achieved_at'] as String),
  );
}

class ProgressSummary {
  const ProgressSummary({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalWorkouts,
    required this.totalVolume,
    required this.personalRecords,
  });

  final int currentStreak;
  final int longestStreak;
  final int totalWorkouts;
  final double totalVolume;
  final List<PersonalRecordEntry> personalRecords;

  factory ProgressSummary.fromJson(Map<String, dynamic> json) => ProgressSummary(
    currentStreak: json['current_streak'] as int,
    longestStreak: json['longest_streak'] as int,
    totalWorkouts: json['total_workouts'] as int,
    totalVolume: (json['total_volume'] as num).toDouble(),
    personalRecords: (json['personal_records'] as List)
        .map((r) => PersonalRecordEntry.fromJson(r as Map<String, dynamic>))
        .toList(),
  );
}

class SessionVolumePoint {
  const SessionVolumePoint({required this.dayName, required this.startedAt, required this.volume});

  final String? dayName;
  final DateTime startedAt;
  final double volume;

  factory SessionVolumePoint.fromJson(Map<String, dynamic> json) => SessionVolumePoint(
    dayName: json['day_name'] as String?,
    startedAt: DateTime.parse(json['started_at'] as String),
    volume: (json['volume'] as num).toDouble(),
  );
}
