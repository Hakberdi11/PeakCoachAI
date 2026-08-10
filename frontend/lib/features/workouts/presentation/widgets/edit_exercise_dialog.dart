import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/workout_models.dart';
import '../../data/workout_repository.dart';

class EditExerciseDialog extends ConsumerStatefulWidget {
  const EditExerciseDialog({super.key, required this.exercise});

  final PlannedExercise exercise;

  @override
  ConsumerState<EditExerciseDialog> createState() => _EditExerciseDialogState();
}

class _EditExerciseDialogState extends ConsumerState<EditExerciseDialog> {
  late final _setsController = TextEditingController(text: '${widget.exercise.targetSets}');
  late final _repsMinController = TextEditingController(text: '${widget.exercise.targetRepsMin}');
  late final _repsMaxController = TextEditingController(text: '${widget.exercise.targetRepsMax}');
  late final _restController = TextEditingController(text: '${widget.exercise.restSeconds}');
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _setsController.dispose();
    _repsMinController.dispose();
    _repsMaxController.dispose();
    _restController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(workoutRepositoryProvider).updateExercise(widget.exercise.id!, {
        'target_sets': int.tryParse(_setsController.text) ?? widget.exercise.targetSets,
        'target_reps_min': int.tryParse(_repsMinController.text) ?? widget.exercise.targetRepsMin,
        'target_reps_max': int.tryParse(_repsMaxController.text) ?? widget.exercise.targetRepsMax,
        'rest_seconds': int.tryParse(_restController.text) ?? widget.exercise.restSeconds,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not save: $e'; _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.exercise.name, style: AppTextStyles.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _setsController,
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.body,
                  decoration: const InputDecoration(labelText: 'Sets'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _restController,
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.body,
                  decoration: const InputDecoration(labelText: 'Rest (s)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _repsMinController,
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.body,
                  decoration: const InputDecoration(labelText: 'Reps min'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _repsMaxController,
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.body,
                  decoration: const InputDecoration(labelText: 'Reps max'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.label.copyWith(color: AppColors.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
