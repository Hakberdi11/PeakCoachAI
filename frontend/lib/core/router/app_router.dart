import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/state/auth_provider.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/ai_profile_creation_screen.dart';
import '../../features/onboarding/presentation/onboarding_flow_screen.dart';
import '../../features/onboarding/state/onboarding_status_provider.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/workouts/presentation/plan_overview_screen.dart';
import '../../features/workouts/presentation/plan_preview_screen.dart';
import '../../features/workouts/presentation/post_workout_reflection_screen.dart';
import '../../features/workouts/presentation/workout_execution_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/onboarding',
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final authStatus = authState.valueOrNull?.status;
      if (authStatus == null) return null; // auth state still loading

      final path = state.matchedLocation;
      final isOnboardingRoute = path.startsWith('/onboarding');
      final isAuthRoute = path == '/login' || path == '/signup';
      final isAuthenticated = authStatus == AuthStatus.authenticated;

      if (!isAuthenticated) {
        // Onboarding, the plan preview, and account creation all work
        // without an account — only unknown routes bounce to onboarding.
        if (isOnboardingRoute || isAuthRoute) return null;
        return '/onboarding';
      }

      final onboardingState = ref.read(onboardingStatusProvider);
      final isOnboarded = onboardingState.valueOrNull;
      if (isOnboarded == null) return null; // onboarding status still loading

      if (!isOnboarded) {
        return isOnboardingRoute ? null : '/onboarding';
      }

      if (isOnboardingRoute || isAuthRoute) return '/';
      return null;
    },
    refreshListenable: GoRouterRefreshNotifier(ref),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/plan', builder: (context, state) => const PlanOverviewScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingFlowScreen(),
      ),
      GoRoute(
        path: '/onboarding/generating',
        builder: (context, state) => const AiProfileCreationScreen(),
      ),
      GoRoute(
        path: '/onboarding/plan',
        builder: (context, state) => const PlanPreviewScreen(),
      ),
      GoRoute(
        path: '/workout/:sessionId',
        builder: (context, state) => WorkoutExecutionScreen(
          sessionId: int.parse(state.pathParameters['sessionId']!),
        ),
      ),
      GoRoute(
        path: '/workout/:sessionId/reflection',
        builder: (context, state) => PostWorkoutReflectionScreen(
          sessionId: int.parse(state.pathParameters['sessionId']!),
        ),
      ),
      GoRoute(path: '/progress', builder: (context, state) => const ProgressScreen()),
    ],
  );
});

/// Notifies go_router to re-run [redirect] whenever auth or onboarding state changes.
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
    ref.listen(onboardingStatusProvider, (_, _) => notifyListeners());
  }
}
