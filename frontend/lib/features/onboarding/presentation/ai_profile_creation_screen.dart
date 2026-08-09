import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/state/auth_provider.dart';
import '../../workouts/data/workout_repository.dart';
import '../../workouts/state/plan_preview_provider.dart';
import '../data/onboarding_repository.dart';
import '../state/onboarding_draft_provider.dart';
import '../state/onboarding_status_provider.dart';

const _messages = [
  'Understanding your goals…',
  'Building your athlete profile…',
  'Designing your first program…',
  'Your coach is getting ready…',
];

class AiProfileCreationScreen extends ConsumerStatefulWidget {
  const AiProfileCreationScreen({super.key});

  @override
  ConsumerState<AiProfileCreationScreen> createState() =>
      _AiProfileCreationScreenState();
}

class _AiProfileCreationScreenState extends ConsumerState<AiProfileCreationScreen> {
  int _messageIndex = 0;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!mounted) return;
      setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
    });
    _run();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final draft = ref.read(onboardingDraftProvider);
      final isAuthenticated =
          ref.read(authProvider).valueOrNull?.status == AuthStatus.authenticated;

      if (isAuthenticated) {
        // Re-onboarding for an already-signed-in user: submit and generate directly.
        await ref.read(onboardingRepositoryProvider).submit(draft);
        await ref.read(onboardingStatusProvider.notifier).markComplete();
        await ref.read(workoutRepositoryProvider).generatePlan();
        if (!mounted) return;
        ref.invalidate(activePlanProvider);
        context.go('/');
        return;
      }

      // First-time visitor: preview the plan before asking for an account.
      final preview = await ref.read(workoutRepositoryProvider).previewPlan(draft);
      ref.read(planPreviewProvider.notifier).state = preview;
      if (!mounted) return;
      context.go('/onboarding/plan');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong building your plan. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error == null) ...[
                  const CircularProgressIndicator(color: AppColors.primaryAccent),
                  const SizedBox(height: 32),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      _messages[_messageIndex],
                      key: ValueKey(_messageIndex),
                      style: AppTextStyles.title,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.error_outline, color: AppColors.error, size: 40),
                  const SizedBox(height: 16),
                  Text(_error!, style: AppTextStyles.body, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _run();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
