import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/session_repository.dart';
import '../data/workout_models.dart';
import '../data/workout_repository.dart';
import 'widgets/add_exercise_sheet.dart';
import 'widgets/edit_exercise_dialog.dart';
import 'widgets/plan_days_list.dart';

class PlanOverviewScreen extends ConsumerStatefulWidget {
  const PlanOverviewScreen({super.key});

  @override
  ConsumerState<PlanOverviewScreen> createState() => _PlanOverviewScreenState();
}

class _PlanOverviewScreenState extends ConsumerState<PlanOverviewScreen> {
  bool _editing = false;
  final _reviseController = TextEditingController();
  bool _revising = false;

  @override
  void dispose() {
    _reviseController.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(activePlanProvider);

  Future<void> _deleteExercise(PlannedExercise exercise) async {
    await ref.read(workoutRepositoryProvider).removeExercise(exercise.id!);
    _refresh();
  }

  Future<void> _editExercise(PlannedExercise exercise) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EditExerciseDialog(exercise: exercise),
    );
    if (saved == true) _refresh();
  }

  Future<void> _addExercise(WorkoutDay day) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => AddExerciseSheet(dayId: day.id!),
    );
    if (added == true) _refresh();
  }

  Future<void> _submitRevision() async {
    final instruction = _reviseController.text.trim();
    if (instruction.isEmpty || _revising) return;
    setState(() => _revising = true);
    try {
      final result = await ref.read(workoutRepositoryProvider).revisePlan(instruction);
      _reviseController.clear();
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.changeSummary.isNotEmpty ? result.changeSummary : 'Plan updated.',
            ),
            backgroundColor: AppColors.surface,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update plan: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _revising = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(activePlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Your Plan', style: AppTextStyles.title),
        actions: [
          planAsync.maybeWhen(
            data: (plan) => plan == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: Icon(_editing ? Icons.check : Icons.edit_outlined, color: AppColors.text),
                    tooltip: _editing ? 'Done editing' : 'Edit plan',
                    onPressed: () => setState(() => _editing = !_editing),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
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
              : Column(
                  children: [
                    Expanded(
                      child: PlanDaysList(
                        plan: plan,
                        editable: _editing,
                        onEditExercise: (_, exercise) => _editExercise(exercise),
                        onDeleteExercise: (_, exercise) => _deleteExercise(exercise),
                        onAddExercise: (day) => _addExercise(day),
                        onStartDay: _editing
                            ? null
                            : (day) async {
                                final session = await ref
                                    .read(sessionRepositoryProvider)
                                    .startSession(day.id!);
                                if (context.mounted) context.push('/workout/${session.id}');
                              },
                      ),
                    ),
                    _ReviseBar(
                      controller: _reviseController,
                      submitting: _revising,
                      onSubmit: _submitRevision,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Persistent "tell the AI what to change" entry point — a single free-text
/// field rather than a multi-turn chat thread, since the app has no existing
/// chat UI pattern to build on yet.
class _ReviseBar extends StatelessWidget {
  const _ReviseBar({required this.controller, required this.submitting, required this.onSubmit});

  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.background, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: AppTextStyles.body,
              enabled: !submitting,
              decoration: const InputDecoration(
                hintText: 'Ask your coach to change this plan…',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          IconButton(
            icon: submitting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryAccent),
                  )
                : const Icon(Icons.arrow_upward, color: AppColors.primaryAccent),
            onPressed: submitting ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}
