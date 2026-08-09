import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/session_models.dart';
import '../data/session_repository.dart';
import '../data/workout_models.dart';

class WorkoutExecutionScreen extends ConsumerStatefulWidget {
  const WorkoutExecutionScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  ConsumerState<WorkoutExecutionScreen> createState() => _WorkoutExecutionScreenState();
}

class _WorkoutExecutionScreenState extends ConsumerState<WorkoutExecutionScreen> {
  final Map<int, TextEditingController> _weightControllers = {};
  final Map<int, TextEditingController> _repsControllers = {};
  bool _finishing = false;

  TextEditingController _weightController(int exerciseId) =>
      _weightControllers.putIfAbsent(exerciseId, TextEditingController.new);

  TextEditingController _repsController(int exerciseId) =>
      _repsControllers.putIfAbsent(exerciseId, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _weightControllers.values) {
      c.dispose();
    }
    for (final c in _repsControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(sessionProvider(widget.sessionId));
  }

  Future<void> _logSet(PlannedExercise exercise, ExerciseLogEntry? log) async {
    final weight = double.tryParse(_weightController(exercise.id!).text);
    final reps = int.tryParse(_repsController(exercise.id!).text);
    if (weight == null || reps == null) return;

    final nextSetNumber = (log?.sets.length ?? 0) + 1;
    final isNewPr = await ref.read(sessionRepositoryProvider).logSet(
      widget.sessionId,
      plannedExerciseId: exercise.id!,
      setNumber: nextSetNumber,
      weight: weight,
      reps: reps,
    );
    _weightController(exercise.id!).clear();
    _repsController(exercise.id!).clear();
    _refresh();

    if (isNewPr && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New personal record on ${exercise.name}!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _skip(PlannedExercise exercise) async {
    await ref.read(sessionRepositoryProvider).skipExercise(widget.sessionId, exercise.id!);
    _refresh();
  }

  Future<void> _replace(PlannedExercise exercise) async {
    final controller = TextEditingController();
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Replace ${exercise.name}', style: AppTextStyles.title),
        content: TextField(
          controller: controller,
          style: AppTextStyles.body,
          decoration: const InputDecoration(hintText: 'New exercise name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await ref.read(sessionRepositoryProvider).replaceExercise(
      widget.sessionId,
      exercise.id!,
      newName,
    );
    _refresh();
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await ref.read(sessionRepositoryProvider).finishSession(widget.sessionId);
    if (!mounted) return;
    context.go('/workout/${widget.sessionId}/reflection');
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider(widget.sessionId));

    return Scaffold(
      appBar: AppBar(title: Text('Workout', style: AppTextStyles.title)),
      body: SafeArea(
        child: sessionAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primaryAccent),
          ),
          error: (error, _) => Center(
            child: Text(
              'Could not load workout: $error',
              style: AppTextStyles.body.copyWith(color: AppColors.error),
            ),
          ),
          data: (session) {
            final day = session.workoutDay;
            if (day == null) {
              return Center(child: Text('No exercises found.', style: AppTextStyles.body));
            }
            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: day.exercises.length,
                    itemBuilder: (context, index) {
                      final exercise = day.exercises[index];
                      final log = session.logFor(exercise.id!);
                      return _ExerciseCard(
                        exercise: exercise,
                        log: log,
                        weightController: _weightController(exercise.id!),
                        repsController: _repsController(exercise.id!),
                        onLogSet: () => _logSet(exercise, log),
                        onSkip: () => _skip(exercise),
                        onReplace: () => _replace(exercise),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: ElevatedButton(
                    onPressed: _finishing ? null : _finish,
                    child: _finishing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
                          )
                        : const Text('Finish Workout'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.log,
    required this.weightController,
    required this.repsController,
    required this.onLogSet,
    required this.onSkip,
    required this.onReplace,
  });

  final PlannedExercise exercise;
  final ExerciseLogEntry? log;
  final TextEditingController weightController;
  final TextEditingController repsController;
  final VoidCallback onLogSet;
  final VoidCallback onSkip;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final isSkipped = log?.status == 'skipped';
    final isReplaced = log?.status == 'replaced';
    final displayName = log?.displayName ?? exercise.name;

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: AppTextStyles.title.copyWith(color: AppColors.primaryAccent),
                  ),
                ),
                Text(
                  '${exercise.targetSets} x ${exercise.targetRepsMin}-${exercise.targetRepsMax}',
                  style: AppTextStyles.label,
                ),
              ],
            ),
            if (isReplaced)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('was ${exercise.name}', style: AppTextStyles.label),
              ),
            const SizedBox(height: 12),
            if (isSkipped)
              Text('Skipped', style: AppTextStyles.body.copyWith(color: AppColors.warning))
            else ...[
              ...?log?.sets.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Set ${s.setNumber}: ${s.weight}kg x ${s.reps}',
                    style: AppTextStyles.body,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: weightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: AppTextStyles.body,
                      decoration: const InputDecoration(hintText: 'kg'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: repsController,
                      keyboardType: TextInputType.number,
                      style: AppTextStyles.body,
                      decoration: const InputDecoration(hintText: 'reps'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(onPressed: onLogSet, child: const Text('Log')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(onPressed: onSkip, child: const Text('Skip')),
                  TextButton(onPressed: onReplace, child: const Text('Replace')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
