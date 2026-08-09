import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/session_repository.dart';
import '../data/workout_repository.dart';

const _difficulties = [
  ('easy', 'Easy'),
  ('good', 'Good'),
  ('hard', 'Hard'),
  ('very_hard', 'Very Hard'),
];

class PostWorkoutReflectionScreen extends ConsumerStatefulWidget {
  const PostWorkoutReflectionScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  ConsumerState<PostWorkoutReflectionScreen> createState() =>
      _PostWorkoutReflectionScreenState();
}

class _PostWorkoutReflectionScreenState
    extends ConsumerState<PostWorkoutReflectionScreen> {
  String? _difficulty;
  final _notesController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_difficulty == null) return;
    setState(() => _submitting = true);
    await ref.read(sessionRepositoryProvider).submitFeedback(
      widget.sessionId,
      difficulty: _difficulty!,
      notes: _notesController.text.trim(),
    );
    ref.invalidate(activePlanProvider);
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Workout complete', style: AppTextStyles.headline),
              const SizedBox(height: 8),
              Text('How did today\'s workout feel?', style: AppTextStyles.body),
              const SizedBox(height: 24),
              ..._difficulties.map(
                (option) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _difficulty = option.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _difficulty == option.$1
                              ? AppColors.primaryAccent
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Text(option.$2, style: AppTextStyles.body),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 3,
                style: AppTextStyles.body,
                decoration: const InputDecoration(hintText: 'Optional notes'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _difficulty == null || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
                      )
                    : const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
