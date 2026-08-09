import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/session_repository.dart';
import '../data/workout_repository.dart';
import 'widgets/plan_days_list.dart';

class PlanOverviewScreen extends ConsumerWidget {
  const PlanOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(activePlanProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Your Plan', style: AppTextStyles.title)),
      body: SafeArea(
        child: planAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primaryAccent),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load your plan: $error',
                style: AppTextStyles.body.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (plan) => plan == null
              ? Center(
                  child: Text('No active plan yet.', style: AppTextStyles.body),
                )
              : PlanDaysList(
                  plan: plan,
                  onStartDay: (day) async {
                    final session = await ref
                        .read(sessionRepositoryProvider)
                        .startSession(day.id!);
                    if (context.mounted) context.push('/workout/${session.id}');
                  },
                ),
        ),
      ),
    );
  }
}
