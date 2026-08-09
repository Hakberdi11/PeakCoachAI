import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../../onboarding/state/onboarding_draft_provider.dart';
import '../../onboarding/state/onboarding_status_provider.dart';
import '../../workouts/data/workout_repository.dart';
import '../../workouts/state/plan_preview_provider.dart';
import '../data/auth_repository.dart';
import '../state/auth_provider.dart';
import 'auth_error.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await repo.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await ref.read(authProvider.notifier).refreshFromStorage();

      final draft = ref.read(onboardingDraftProvider);
      await ref.read(onboardingRepositoryProvider).submit(draft);

      final preview = ref.read(planPreviewProvider);
      final workoutRepo = ref.read(workoutRepositoryProvider);
      if (preview != null) {
        await workoutRepo.savePreview(preview);
      } else {
        await workoutRepo.generatePlan();
      }

      await ref.read(onboardingStatusProvider.notifier).markComplete();
      ref.invalidate(activePlanProvider);
    } on DioException catch (e) {
      setState(() => _error = extractAuthError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Peak Coach AI', style: AppTextStyles.headline, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('Create your account', style: AppTextStyles.body, textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: AppTextStyles.body,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) =>
                        (value == null || !value.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: AppTextStyles.body,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (value) =>
                        (value == null || value.length < 8) ? 'At least 8 characters' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.error)),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
                          )
                        : const Text('Sign up'),
                  ),
                  const SizedBox(height: 16),
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
          ),
        ),
      ),
    );
  }
}
