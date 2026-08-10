import math
from datetime import timedelta

from django.utils import timezone

from ..models import WorkoutStreak


def _grace_days(training_days: int | None) -> int:
    """How many calendar days a gap can span before we consider the streak
    broken, derived from the athlete's own planned training frequency instead
    of assuming every day (or strictly yesterday) is a training day."""
    if not training_days:
        return 2
    return math.ceil(7 / training_days) + 1


def update_streak_on_finish(user) -> WorkoutStreak:
    from apps.onboarding.models import OnboardingProfile

    streak, _ = WorkoutStreak.objects.get_or_create(user=user)
    today = timezone.localdate()
    profile = OnboardingProfile.objects.filter(user=user).only('training_days').first()
    grace = _grace_days(profile.training_days if profile else None)

    if streak.last_workout_date == today:
        pass  # already counted today
    elif streak.last_workout_date is not None and (today - streak.last_workout_date).days <= grace:
        streak.current_streak += 1
    else:
        streak.current_streak = 1

    streak.longest_streak = max(streak.longest_streak, streak.current_streak)
    streak.last_workout_date = today
    streak.save(update_fields=['current_streak', 'longest_streak', 'last_workout_date'])
    return streak


def rolling_completion_rate(user, window_days: int = 28) -> float:
    """Sessions completed / sessions expected over a trailing window, based on
    the athlete's own training_days target. More resilient than a raw streak
    to a single missed day — recommended in the habits research as the primary
    adherence signal, with streak as a secondary/supporting metric."""
    from apps.onboarding.models import OnboardingProfile
    from apps.workouts.models import WorkoutSession

    profile = OnboardingProfile.objects.filter(user=user).only('training_days').first()
    training_days = profile.training_days if profile else 3

    window_start = timezone.now() - timedelta(days=window_days)
    completed = WorkoutSession.objects.filter(
        user=user, status=WorkoutSession.Status.COMPLETED, started_at__gte=window_start
    ).count()

    expected = round(training_days * window_days / 7)
    if expected <= 0:
        return 0.0
    return min(1.0, completed / expected)
