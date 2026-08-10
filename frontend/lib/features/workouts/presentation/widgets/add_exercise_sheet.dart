import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/workout_models.dart';
import '../../data/workout_repository.dart';

/// Bottom sheet for the manual "add exercise" flow: pick from the curated
/// catalog (or type a freeform name, matching how the AI already produces
/// freeform names) and set sets/reps/rest, then submit directly.
class AddExerciseSheet extends ConsumerStatefulWidget {
  const AddExerciseSheet({super.key, required this.dayId});

  final int dayId;

  @override
  ConsumerState<AddExerciseSheet> createState() => _AddExerciseSheetState();
}

class _AddExerciseSheetState extends ConsumerState<AddExerciseSheet> {
  final _nameController = TextEditingController();
  final _setsController = TextEditingController(text: '3');
  final _repsMinController = TextEditingController(text: '8');
  final _repsMaxController = TextEditingController(text: '12');
  final _restController = TextEditingController(text: '60');

  List<ExerciseCatalogEntry> _catalog = [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final entries = await ref.read(workoutRepositoryProvider).fetchExerciseCatalog();
      if (mounted) setState(() { _catalog = entries; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _setsController.dispose();
    _repsMinController.dispose();
    _repsMaxController.dispose();
    _restController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Choose or type an exercise name.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(workoutRepositoryProvider).addExercise(
        widget.dayId,
        exerciseName: name,
        targetSets: int.tryParse(_setsController.text) ?? 3,
        targetRepsMin: int.tryParse(_repsMinController.text) ?? 8,
        targetRepsMax: int.tryParse(_repsMaxController.text) ?? 12,
        restSeconds: int.tryParse(_restController.text) ?? 60,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not add exercise: $e'; _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add exercise', style: AppTextStyles.title),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            style: AppTextStyles.body,
            decoration: const InputDecoration(labelText: 'Exercise name'),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(color: AppColors.primaryAccent),
            )
          else if (_catalog.isNotEmpty)
            SizedBox(
              height: 160,
              child: ListView.builder(
                itemCount: _catalog.length,
                itemBuilder: (context, index) {
                  final entry = _catalog[index];
                  return ListTile(
                    dense: true,
                    title: Text(entry.name, style: AppTextStyles.body),
                    subtitle: Text(entry.muscleGroup, style: AppTextStyles.label),
                    onTap: () => setState(() => _nameController.text = entry.name),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
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
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.label.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Adding…' : 'Add'),
          ),
        ],
      ),
    );
  }
}
