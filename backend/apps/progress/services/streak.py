from datetime import timedelta

from django.utils import timezone

from ..models import WorkoutStreak


def update_streak_on_finish(user) -> WorkoutStreak:
    streak, _ = WorkoutStreak.objects.get_or_create(user=user)
    today = timezone.localdate()

    if streak.last_workout_date == today:
        pass  # already counted today
    elif streak.last_workout_date == today - timedelta(days=1):
        streak.current_streak += 1
    else:
        streak.current_streak = 1

    streak.longest_streak = max(streak.longest_streak, streak.current_streak)
    streak.last_workout_date = today
    streak.save(update_fields=['current_streak', 'longest_streak', 'last_workout_date'])
    return streak
