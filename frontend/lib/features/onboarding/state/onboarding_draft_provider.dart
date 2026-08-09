import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_draft.dart';

class OnboardingDraftNotifier extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() => const OnboardingDraft();

  void update(OnboardingDraft Function(OnboardingDraft) updater) {
    state = updater(state);
  }
}

final onboardingDraftProvider =
    NotifierProvider<OnboardingDraftNotifier, OnboardingDraft>(
      OnboardingDraftNotifier.new,
    );
