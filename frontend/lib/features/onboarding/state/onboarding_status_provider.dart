import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_provider.dart';
import '../data/onboarding_repository.dart';

class OnboardingStatusNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final auth = await ref.watch(authProvider.future);
    if (auth.status != AuthStatus.authenticated) return false;
    return ref.read(onboardingRepositoryProvider).isComplete();
  }

  Future<void> markComplete() async {
    state = const AsyncData(true);
  }
}

final onboardingStatusProvider =
    AsyncNotifierProvider<OnboardingStatusNotifier, bool>(
      OnboardingStatusNotifier.new,
    );
