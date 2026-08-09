import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/state/auth_provider.dart';
import '../../insights/data/insights_repository.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../../progress/data/progress_repository.dart';
import '../../workouts/data/session_repository.dart';
import '../../workouts/data/workout_repository.dart';

const _goalLabels = {
  'build_muscle': 'Build Muscle',
  'lose_fat': 'Lose Fat',
  'increase_strength': 'Increase Strength',
  'improve_fitness': 'Improve Fitness',
  'build_habits': 'Build Healthy Habits',
};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(activePlanProvider);
    final summaryAsync = ref.watch(progressSummaryProvider);
    final insightsAsync = ref.watch(latestInsightsProvider);
    final profileAsync = ref.watch(onboardingProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Peak Coach AI', style: AppTextStyles.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt, color: AppColors.text),
            onPressed: () => context.push('/plan'),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart, color: AppColors.text),
            onPressed: () => context.push('/progress'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.text),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Welcome back', style: AppTextStyles.headline),
            const SizedBox(height: 4),
            profileAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (profile) {
                final goal = profile?['goal'] as String?;
                if (goal == null) return const SizedBox.shrink();
                return Text(
                  'Goal: ${_goalLabels[goal] ?? goal}',
                  style: AppTextStyles.body,
                );
              },
            ),
            const SizedBox(height: 24),
            summaryAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (summary) => Row(
                children: [
                  Expanded(
                    child: _StatTile(label: 'Streak', value: '${summary.currentStreak}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(label: 'Workouts', value: '${summary.totalWorkouts}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      label: 'Volume',
                      value: '${summary.totalVolume.toStringAsFixed(0)}kg',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Next Workout', style: AppTextStyles.title),
            const SizedBox(height: 12),
            planAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primaryAccent),
              ),
              error: (error, _) => Text(
                'Could not load your plan.',
                style: AppTextStyles.body.copyWith(color: AppColors.error),
              ),
              data: (plan) {
                if (plan == null || plan.days.isEmpty) {
                  return Text('No active plan yet.', style: AppTextStyles.body);
                }
                final day = plan.days.first;
                return Card(
                  color: AppColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          day.name,
                          style: AppTextStyles.title.copyWith(color: AppColors.primaryAccent),
                        ),
                        const SizedBox(height: 4),
                        Text('${day.exercises.length} exercises', style: AppTextStyles.label),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () async {
                            final session = await ref
                                .read(sessionRepositoryProvider)
                                .startSession(day.id!);
                            if (context.mounted) {
                              context.push('/workout/${session.id}');
                            }
                          },
                          child: const Text('Start Workout'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text('AI Insight', style: AppTextStyles.title),
            const SizedBox(height: 12),
            insightsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primaryAccent),
              ),
              error: (_, _) => Text(
                'Your coach will have insights after a few workouts.',
                style: AppTextStyles.body,
              ),
              data: (insights) => insights.isEmpty
                  ? Text(
                      'Complete a few workouts to unlock AI insights.',
                      style: AppTextStyles.body,
                    )
                  : Column(
                      children: insights
                          .map(
                            (insight) => Card(
                              color: AppColors.surface,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(insight.text, style: AppTextStyles.body),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Text(value, style: AppTextStyles.title),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.label),
          ],
        ),
      ),
    );
  }
}
