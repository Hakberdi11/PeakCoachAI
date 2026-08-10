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

const _minWorkoutDuration = 15;
const _maxWorkoutDuration = 120;

/// One onboarding screen: what to show and whether "Continue" is enabled.
/// Steps are computed per-build from the current draft rather than picked out
/// of a hardcoded switch, so a step can be conditionally included later
/// (e.g. per-goal follow-ups) without restructuring this screen.
class _Step {
  const _Step({required this.title, required this.nextEnabled, required this.child, this.nextLabel});

  final String title;
  final bool nextEnabled;
  final Widget child;
  final String? nextLabel;
}

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

  void _updateDraft(OnboardingDraft Function(OnboardingDraft) updater) {
    ref.read(onboardingDraftProvider.notifier).update(updater);
  }

  List<_Step> _buildSteps(OnboardingDraft draft) {
    return [
      _Step(
        title: 'What does your peak look like?',
        nextEnabled: draft.goal != null,
        child: SingleChoiceList(
          options: _goalOptions,
          selected: draft.goal,
          onChanged: (v) => _updateDraft((d) => d.copyWith(goal: v)),
        ),
      ),
      _Step(
        title: 'What motivates you most?',
        nextEnabled: draft.motivation != null,
        child: SingleChoiceList(
          options: _motivationOptions,
          selected: draft.motivation,
          onChanged: (v) => _updateDraft((d) => d.copyWith(motivation: v)),
        ),
      ),
      _Step(
        title: 'What is your experience level?',
        nextEnabled: draft.experience != null,
        child: SingleChoiceList(
          options: _experienceOptions,
          selected: draft.experience,
          onChanged: (v) => _updateDraft((d) => d.copyWith(experience: v)),
        ),
      ),
      _Step(
        title: 'Tell us about yourself',
        nextEnabled: draft.age != null &&
            draft.gender != null &&
            draft.heightCm != null &&
            draft.weightKg != null,
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
              onChanged: (v) => _updateDraft((d) => d.copyWith(heightCm: double.tryParse(v))),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTextStyles.body,
              decoration: const InputDecoration(labelText: 'Weight (kg)'),
              onChanged: (v) => _updateDraft((d) => d.copyWith(weightKg: double.tryParse(v))),
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
      ),
      _Step(
        title: 'Where do you train?',
        nextEnabled: draft.trainingEnvironment != null,
        child: SingleChoiceList(
          options: _environmentOptions,
          selected: draft.trainingEnvironment,
          onChanged: (v) => _updateDraft((d) => d.copyWith(trainingEnvironment: v)),
        ),
      ),
      _Step(
        title: 'What equipment do you have access to?',
        nextEnabled: draft.equipment.isNotEmpty,
        child: MultiChoiceList(
          options: _equipmentOptions,
          selected: draft.equipment,
          onChanged: (v) => _updateDraft((d) => d.copyWith(equipment: v)),
        ),
      ),
      _Step(
        title: 'How many days per week can you train?',
        nextEnabled: draft.trainingDays != null,
        child: _SliderStep(
          value: (draft.trainingDays ?? 3).toDouble(),
          min: 2,
          max: 6,
          divisions: 4,
          label: (v) => '${v.round()} days / week',
          onChanged: (v) => _updateDraft((d) => d.copyWith(trainingDays: v.round())),
        ),
      ),
      _Step(
        title: 'How long should your workouts be?',
        nextEnabled: draft.workoutDuration != null,
        child: _SliderStep(
          value: (draft.workoutDuration ?? 45).toDouble(),
          min: _minWorkoutDuration.toDouble(),
          max: _maxWorkoutDuration.toDouble(),
          divisions: (_maxWorkoutDuration - _minWorkoutDuration) ~/ 5,
          label: (v) => '${v.round()} min',
          onChanged: (v) => _updateDraft((d) => d.copyWith(workoutDuration: v.round())),
        ),
      ),
      _Step(
        title: 'Which muscles matter most to you?',
        nextEnabled: draft.priorityMuscles.isNotEmpty,
        child: MultiChoiceList(
          options: _muscleOptions,
          selected: draft.priorityMuscles,
          onChanged: (v) => _updateDraft((d) => d.copyWith(priorityMuscles: v)),
        ),
      ),
      _Step(
        title: 'Any injuries or limitations?',
        nextEnabled: true,
        nextLabel: 'Continue',
        child: TextField(
          controller: _injuriesController,
          maxLines: 4,
          style: AppTextStyles.body,
          decoration: const InputDecoration(
            hintText: 'Optional — let your coach know about anything to work around',
          ),
          onChanged: (v) => _updateDraft((d) => d.copyWith(injuries: v)),
        ),
      ),
      _Step(
        title: 'How should your coach talk to you?',
        nextEnabled: draft.coachPersonality != null,
        nextLabel: 'Build my plan',
        child: SingleChoiceList(
          options: _personalityOptions,
          selected: draft.coachPersonality,
          onChanged: (v) => _updateDraft((d) => d.copyWith(coachPersonality: v)),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final steps = _buildSteps(draft);
    final stepCount = steps.length;
    final step = steps[_step];

    void next() {
      if (_step == stepCount - 1) {
        context.go('/onboarding/generating');
        return;
      }
      setState(() => _step++);
    }

    void back() {
      if (_step == 0) return;
      setState(() => _step--);
    }

    return OnboardingStepScaffold(
      title: step.title,
      stepIndex: _step,
      stepCount: stepCount,
      nextEnabled: step.nextEnabled,
      nextLabel: step.nextLabel ?? 'Continue',
      onNext: next,
      onBack: _step == 0 ? null : back,
      child: step.child,
    );
  }
}

class _SliderStep extends StatelessWidget {
  const _SliderStep({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label(value), style: AppTextStyles.headline),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppColors.primaryAccent,
          label: label(value),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
