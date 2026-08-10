from ..models import AdaptationHistory

# For a fat-loss athlete, the research is explicit: protect load during a
# deficit rather than backing off after an ordinary rough set. Everyone else
# gets a majority-of-sets-missed threshold instead of the old fixed
# "2 failed sets" rule, which used to fire on a perfectly normal heavy 5x3 day.
_DECREASE_LOAD_RATIO = {
    'lose_fat': 0.75,
}
_DEFAULT_DECREASE_LOAD_RATIO = 0.5


def _athlete_goal(user) -> str:
    from apps.onboarding.models import OnboardingProfile

    profile = OnboardingProfile.objects.filter(user=user).only('goal').first()
    return profile.goal if profile else ''


def evaluate_reps(session):
    """Rule-based, per-exercise: repeated rep failures/overshoots adjust load next time."""
    decisions = []
    goal = _athlete_goal(session.user)
    threshold_ratio = _DECREASE_LOAD_RATIO.get(goal, _DEFAULT_DECREASE_LOAD_RATIO)

    for log in session.exercise_logs.all():
        if log.status == 'skipped' or log.planned_exercise_id is None:
            continue

        sets = list(log.sets.all())
        if not sets:
            continue

        planned = log.planned_exercise
        active_name = log.replaced_with_name or log.exercise_name

        failed = sum(1 for s in sets if s.reps < planned.target_reps_min)
        exceeded_all = all(s.reps > planned.target_reps_max for s in sets)

        if failed / len(sets) >= threshold_ratio:
            decisions.append(
                AdaptationHistory(
                    user=session.user,
                    workout_session=session,
                    exercise_name=active_name,
                    decision=AdaptationHistory.Decision.DECREASE_LOAD,
                    reason=f'Missed target reps in {failed} of {len(sets)} sets.',
                )
            )
        elif exceeded_all:
            decisions.append(
                AdaptationHistory(
                    user=session.user,
                    workout_session=session,
                    exercise_name=active_name,
                    decision=AdaptationHistory.Decision.INCREASE_LOAD,
                    reason='Exceeded target reps in every set.',
                )
            )

    AdaptationHistory.objects.bulk_create(decisions)
    return decisions


def evaluate_feedback(session, feedback):
    """Session-level: repeated hard/very-hard feedback lowers next plan's volume.
    Windowed to recent history so a bad stretch from months ago can't still be
    triggering a volume cut today."""
    from datetime import timedelta

    from django.utils import timezone

    from apps.workouts.models import WorkoutFeedback

    window_start = timezone.now() - timedelta(days=21)
    recent = list(
        WorkoutFeedback.objects.filter(session__user=session.user, created_at__gte=window_start)
        .order_by('-created_at')[:3]
    )
    hard_count = sum(1 for f in recent if f.difficulty in ('hard', 'very_hard'))

    if len(recent) >= 2 and hard_count == len(recent):
        return AdaptationHistory.objects.create(
            user=session.user,
            workout_session=session,
            exercise_name='',
            decision=AdaptationHistory.Decision.DECREASE_VOLUME,
            reason=f'Last {len(recent)} workouts (within 21 days) rated hard or very hard.',
        )
    return None
