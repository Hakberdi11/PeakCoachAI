import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../state/onboarding_draft.dart';
import '../state/onboarding_draft_provider.dart';
import 'widgets/choice_option.dart';
import 'widgets/multi_choice_list.dart';
import 'widgets/onboarding_step_scaffold.dart';
import 'widgets/single_choice_list.dart';

const _goalOptions = [
  ChoiceOption('build_muscle', 'Build Muscle'),
  ChoiceOption('lose_fat', 'Lose Fat'),
  ChoiceOption('increase_strength', 'Increase Strength'),
  ChoiceOption('improve_fitness', 'Improve Fitness'),
  ChoiceOption('build_habits', 'Build Healthy Habits'),
];

const _motivationOptions = [
  ChoiceOption('looking_better', 'Looking Better'),
  ChoiceOption('lifting_heavier', 'Lifting Heavier'),
  ChoiceOption('consistency', 'Consistency'),
  ChoiceOption('health', 'Health'),
  ChoiceOption('athletic_performance', 'Athletic Performance'),
];

const _experienceOptions = [
  ChoiceOption('beginner', 'Beginner'),
  ChoiceOption('intermediate', 'Intermediate'),
  ChoiceOption('advanced', 'Advanced'),
];

const _genderOptions = [
  ChoiceOption('male', 'Male'),
  ChoiceOption('female', 'Female'),
  ChoiceOption('other', 'Other'),
];

const _environmentOptions = [
  ChoiceOption('commercial_gym', 'Commercial Gym'),
  ChoiceOption('home_gym', 'Home Gym'),
  ChoiceOption('limited_equipment', 'Limited Equipment'),
];

const _equipmentOptions = [
  ChoiceOption('barbell', 'Barbell'),
  ChoiceOption('dumbbells', 'Dumbbells'),
  ChoiceOption('machines', 'Machines'),
  ChoiceOption('cables', 'Cables'),
  ChoiceOption('pull_up_bar', 'Pull-up Bar'),
  ChoiceOption('resistance_bands', 'Resistance Bands'),
];

const _durationOptions = [
  ChoiceOption('30', '30 min'),
  ChoiceOption('45', '45 min'),
  ChoiceOption('60', '60 min'),
  ChoiceOption('90+', '90+ min'),
];

const _styleOptions = [
  ChoiceOption('high_intensity', 'High Intensity'),
  ChoiceOption('progressive_overload', 'Progressive Overload'),
  ChoiceOption('high_volume', 'High Volume'),
  ChoiceOption('balanced', 'Balanced'),
];

const _muscleOptions = [
  ChoiceOption('chest', 'Chest'),
  ChoiceOption('back', 'Back'),
  ChoiceOption('shoulders', 'Shoulders'),
  ChoiceOption('arms', 'Arms'),
  ChoiceOption('legs', 'Legs'),
  ChoiceOption('core', 'Core'),
];

const _personalityOptions = [
  ChoiceOption('direct', 'Direct'),
  ChoiceOption('supportive', 'Supportive'),
  ChoiceOption('balanced', 'Balanced'),
  ChoiceOption('adaptive', 'Adaptive'),
];

const _stepCount = 12;

class OnboardingFlowScreen extends ConsumerStatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  ConsumerState<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends ConsumerState<OnboardingFlowScreen> {
  int _step = 0;

  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _injuriesController = TextEditingController();

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _injuriesController.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == _stepCount - 1) {
      context.go('/onboarding/generating');
      return;
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
  }

  void _updateDraft(OnboardingDraft Function(OnboardingDraft) updater) {
    ref.read(onboardingDraftProvider.notifier).update(updater);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);

    switch (_step) {
      case 0:
        return OnboardingStepScaffold(
          title: 'What does your peak look like?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.goal != null,
          onNext: _next,
          child: SingleChoiceList(
            options: _goalOptions,
            selected: draft.goal,
            onChanged: (v) => _updateDraft((d) => d.copyWith(goal: v)),
          ),
        );
      case 1:
        return OnboardingStepScaffold(
          title: 'What motivates you most?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.motivation != null,
          onNext: _next,
          onBack: _back,
          child: SingleChoiceList(
            options: _motivationOptions,
            selected: draft.motivation,
            onChanged: (v) => _updateDraft((d) => d.copyWith(motivation: v)),
          ),
        );
      case 2:
        return OnboardingStepScaffold(
          title: 'What is your experience level?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.experience != null,
          onNext: _next,
          onBack: _back,
          child: SingleChoiceList(
            options: _experienceOptions,
            selected: draft.experience,
            onChanged: (v) => _updateDraft((d) => d.copyWith(experience: v)),
          ),
        );
      case 3:
        final valid = draft.age != null &&
            draft.gender != null &&
            draft.heightCm != null &&
            draft.weightKg != null;
        return OnboardingStepScaffold(
          title: 'Tell us about yourself',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: valid,
          onNext: _next,
          onBack: _back,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                style: AppTextStyles.body,
                decoration: const InputDecoration(labelText: 'Age'),
                onChanged: (v) => _updateDraft((d) => d.copyWith(age: int.tryParse(v))),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _heightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: AppTextStyles.body,
                decoration: const InputDecoration(labelText: 'Height (cm)'),
                onChanged: (v) =>
                    _updateDraft((d) => d.copyWith(heightCm: double.tryParse(v))),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: AppTextStyles.body,
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
                onChanged: (v) =>
                    _updateDraft((d) => d.copyWith(weightKg: double.tryParse(v))),
              ),
              const SizedBox(height: 24),
              Text('Gender', style: AppTextStyles.label),
              const SizedBox(height: 12),
              SingleChoiceList(
                options: _genderOptions,
                selected: draft.gender,
                onChanged: (v) => _updateDraft((d) => d.copyWith(gender: v)),
              ),
            ],
          ),
        );
      case 4:
        return OnboardingStepScaffold(
          title: 'Where do you train?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.trainingEnvironment != null,
          onNext: _next,
          onBack: _back,
          child: SingleChoiceList(
            options: _environmentOptions,
            selected: draft.trainingEnvironment,
            onChanged: (v) => _updateDraft((d) => d.copyWith(trainingEnvironment: v)),
          ),
        );
      case 5:
        return OnboardingStepScaffold(
          title: 'What equipment do you have access to?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.equipment.isNotEmpty,
          onNext: _next,
          onBack: _back,
          child: MultiChoiceList(
            options: _equipmentOptions,
            selected: draft.equipment,
            onChanged: (v) => _updateDraft((d) => d.copyWith(equipment: v)),
          ),
        );
      case 6:
        final days = draft.trainingDays ?? 3;
        return OnboardingStepScaffold(
          title: 'How many days per week can you train?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.trainingDays != null,
          onNext: _next,
          onBack: _back,
          child: Column(
            children: [
              Text('$days days / week', style: AppTextStyles.headline),
              Slider(
                value: days.toDouble(),
                min: 2,
                max: 6,
                divisions: 4,
                activeColor: AppColors.primaryAccent,
                label: '$days',
                onChanged: (v) =>
                    _updateDraft((d) => d.copyWith(trainingDays: v.round())),
              ),
            ],
          ),
        );
      case 7:
        return OnboardingStepScaffold(
          title: 'How long should your workouts be?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.workoutDuration != null,
          onNext: _next,
          onBack: _back,
          child: SingleChoiceList(
            options: _durationOptions,
            selected: draft.workoutDuration,
            onChanged: (v) => _updateDraft((d) => d.copyWith(workoutDuration: v)),
          ),
        );
      case 8:
        return OnboardingStepScaffold(
          title: 'What training style fits you?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.trainingStyle != null,
          onNext: _next,
          onBack: _back,
          child: SingleChoiceList(
            options: _styleOptions,
            selected: draft.trainingStyle,
            onChanged: (v) => _updateDraft((d) => d.copyWith(trainingStyle: v)),
          ),
        );
      case 9:
        return OnboardingStepScaffold(
          title: 'Which muscles matter most to you?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.priorityMuscles.isNotEmpty,
          onNext: _next,
          onBack: _back,
          child: MultiChoiceList(
            options: _muscleOptions,
            selected: draft.priorityMuscles,
            onChanged: (v) => _updateDraft((d) => d.copyWith(priorityMuscles: v)),
          ),
        );
      case 10:
        return OnboardingStepScaffold(
          title: 'Any injuries or limitations?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: true,
          nextLabel: 'Continue',
          onNext: _next,
          onBack: _back,
          child: TextField(
            controller: _injuriesController,
            maxLines: 4,
            style: AppTextStyles.body,
            decoration: const InputDecoration(
              hintText: 'Optional — let your coach know about anything to work around',
            ),
            onChanged: (v) => _updateDraft((d) => d.copyWith(injuries: v)),
          ),
        );
      case 11:
      default:
        return OnboardingStepScaffold(
          title: 'How should your coach talk to you?',
          stepIndex: _step,
          stepCount: _stepCount,
          nextEnabled: draft.coachPersonality != null,
          nextLabel: 'Build my plan',
          onNext: _next,
          onBack: _back,
          child: SingleChoiceList(
            options: _personalityOptions,
            selected: draft.coachPersonality,
            onChanged: (v) => _updateDraft((d) => d.copyWith(coachPersonality: v)),
          ),
        );
    }
  }
}
