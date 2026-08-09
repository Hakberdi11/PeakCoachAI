import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/workout_models.dart';

class PlanDaysList extends StatelessWidget {
  const PlanDaysList({
    super.key,
    required this.plan,
    this.padding = const EdgeInsets.all(24),
    this.onStartDay,
  });

  final WorkoutPlan plan;
  final EdgeInsets padding;
  final void Function(WorkoutDay day)? onStartDay;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: plan.days.length,
      itemBuilder: (context, index) {
        final day = plan.days[index];
        return Card(
          color: AppColors.surface,
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Day ${index + 1} — ${day.name}',
                  style: AppTextStyles.title.copyWith(color: AppColors.primaryAccent),
                ),
                const SizedBox(height: 12),
                ...day.exercises.map(
                  (exercise) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(exercise.name, style: AppTextStyles.body)),
                        Text(
                          '${exercise.targetSets} x ${exercise.targetRepsMin}-${exercise.targetRepsMax}',
                          style: AppTextStyles.label,
                        ),
                      ],
                    ),
                  ),
                ),
                if (onStartDay != null) ...[
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => onStartDay!(day),
                    child: const Text('Start Workout'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
