class OnboardingDraft {
  const OnboardingDraft({
    this.goal,
    this.motivation,
    this.experience,
    this.age,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.trainingEnvironment,
    this.equipment = const [],
    this.trainingDays,
    this.workoutDuration,
    this.trainingStyle,
    this.priorityMuscles = const [],
    this.injuries = '',
    this.coachPersonality,
  });

  final String? goal;
  final String? motivation;
  final String? experience;
  final int? age;
  final String? gender;
  final double? heightCm;
  final double? weightKg;
  final String? trainingEnvironment;
  final List<String> equipment;
  final int? trainingDays;
  final String? workoutDuration;
  final String? trainingStyle;
  final List<String> priorityMuscles;
  final String injuries;
  final String? coachPersonality;

  OnboardingDraft copyWith({
    String? goal,
    String? motivation,
    String? experience,
    int? age,
    String? gender,
    double? heightCm,
    double? weightKg,
    String? trainingEnvironment,
    List<String>? equipment,
    int? trainingDays,
    String? workoutDuration,
    String? trainingStyle,
    List<String>? priorityMuscles,
    String? injuries,
    String? coachPersonality,
  }) {
    return OnboardingDraft(
      goal: goal ?? this.goal,
      motivation: motivation ?? this.motivation,
      experience: experience ?? this.experience,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      trainingEnvironment: trainingEnvironment ?? this.trainingEnvironment,
      equipment: equipment ?? this.equipment,
      trainingDays: trainingDays ?? this.trainingDays,
      workoutDuration: workoutDuration ?? this.workoutDuration,
      trainingStyle: trainingStyle ?? this.trainingStyle,
      priorityMuscles: priorityMuscles ?? this.priorityMuscles,
      injuries: injuries ?? this.injuries,
      coachPersonality: coachPersonality ?? this.coachPersonality,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'goal': goal,
      'motivation': motivation,
      'experience': experience,
      'age': age,
      'gender': gender,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'training_environment': trainingEnvironment,
      'equipment': equipment,
      'training_days': trainingDays,
      'workout_duration': workoutDuration,
      'training_style': trainingStyle,
      'priority_muscles': priorityMuscles,
      'injuries': injuries,
      'coach_personality': coachPersonality,
    };
  }
}
