import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class OnboardingStepScaffold extends StatelessWidget {
  const OnboardingStepScaffold({
    super.key,
    required this.title,
    required this.stepIndex,
    required this.stepCount,
    required this.child,
    required this.onNext,
    this.onBack,
    this.nextEnabled = true,
    this.nextLabel = 'Continue',
  });

  final String title;
  final int stepIndex;
  final int stepCount;
  final Widget child;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final bool nextEnabled;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back, color: AppColors.text),
                    ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (stepIndex + 1) / stepCount,
                        backgroundColor: AppColors.surface,
                        color: AppColors.primaryAccent,
                        minHeight: 6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(title, style: AppTextStyles.headline),
              const SizedBox(height: 24),
              Expanded(child: SingleChildScrollView(child: child)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: nextEnabled ? onNext : null,
                child: Text(nextLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
