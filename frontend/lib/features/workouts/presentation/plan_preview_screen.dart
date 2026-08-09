import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_text_styles.dart';
import '../data/workout_models.dart';
import '../state/plan_preview_provider.dart';
import 'widgets/plan_days_list.dart';

class PlanPreviewScreen extends ConsumerWidget {
  const PlanPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = ref.watch(planPreviewProvider);

    if (raw == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "We couldn't find your plan. Let's build it again.",
                    style: AppTextStyles.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/onboarding'),
                    child: const Text('Start over'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final plan = WorkoutPlan.fromJson(raw);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your plan is ready', style: AppTextStyles.headline),
                  const SizedBox(height: 8),
                  Text(
                    'Built by your AI coach from what you just told us.',
                    style: AppTextStyles.body,
                  ),
                ],
              ),
            ),
            Expanded(child: PlanDaysList(plan: plan)),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: () => context.go('/signup'),
                    child: const Text('Create free account to save this plan'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(
                      'Already have an account? Log in',
                      style: AppTextStyles.label,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
