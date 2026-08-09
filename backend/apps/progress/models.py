from django.conf import settings
from django.db import models


class WorkoutStreak(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='workout_streak'
    )
    current_streak = models.PositiveIntegerField(default=0)
    longest_streak = models.PositiveIntegerField(default=0)
    last_workout_date = models.DateField(null=True, blank=True)

    def __str__(self):
        return f'WorkoutStreak(user={self.user_id}, current={self.current_streak})'


class PersonalRecord(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='personal_records'
    )
    exercise_name = models.CharField(max_length=150)
    weight = models.FloatField()
    reps = models.PositiveSmallIntegerField()
    session = models.ForeignKey(
        'workouts.WorkoutSession', on_delete=models.CASCADE, related_name='personal_records'
    )
    achieved_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-achieved_at']

    def __str__(self):
        return f'{self.exercise_name}: {self.weight}x{self.reps} (user={self.user_id})'
