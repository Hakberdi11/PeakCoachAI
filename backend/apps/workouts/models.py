from django.conf import settings
from django.db import models


class WorkoutPlan(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='workout_plans'
    )
    created_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)
    source = models.CharField(max_length=16, default='ai')
    raw_ai_response = models.JSONField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'WorkoutPlan(user={self.user_id}, active={self.is_active})'


class WorkoutDay(models.Model):
    plan = models.ForeignKey(WorkoutPlan, on_delete=models.CASCADE, related_name='days')
    order = models.PositiveSmallIntegerField()
    name = models.CharField(max_length=100)

    class Meta:
        ordering = ['order']

    def __str__(self):
        return f'{self.name} (plan={self.plan_id})'


class PlannedExercise(models.Model):
    day = models.ForeignKey(WorkoutDay, on_delete=models.CASCADE, related_name='exercises')
    order = models.PositiveSmallIntegerField()
    exercise_name = models.CharField(max_length=150)
    target_sets = models.PositiveSmallIntegerField()
    target_reps_min = models.PositiveSmallIntegerField()
    target_reps_max = models.PositiveSmallIntegerField()
    rest_seconds = models.PositiveSmallIntegerField(default=90)
    notes = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ['order']

    def __str__(self):
        return self.exercise_name


class WorkoutSession(models.Model):
    class Status(models.TextChoices):
        IN_PROGRESS = 'in_progress', 'In Progress'
        COMPLETED = 'completed', 'Completed'
        ABANDONED = 'abandoned', 'Abandoned'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='workout_sessions'
    )
    workout_day = models.ForeignKey(
        WorkoutDay, on_delete=models.SET_NULL, null=True, blank=True, related_name='sessions'
    )
    started_at = models.DateTimeField(auto_now_add=True)
    finished_at = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.IN_PROGRESS)

    class Meta:
        ordering = ['-started_at']

    def __str__(self):
        return f'WorkoutSession(user={self.user_id}, status={self.status})'


class ExerciseLog(models.Model):
    class Status(models.TextChoices):
        IN_PROGRESS = 'in_progress', 'In Progress'
        COMPLETED = 'completed', 'Completed'
        SKIPPED = 'skipped', 'Skipped'
        REPLACED = 'replaced', 'Replaced'

    session = models.ForeignKey(
        WorkoutSession, on_delete=models.CASCADE, related_name='exercise_logs'
    )
    planned_exercise = models.ForeignKey(
        PlannedExercise, on_delete=models.SET_NULL, null=True, blank=True, related_name='logs'
    )
    exercise_name = models.CharField(max_length=150)
    replaced_with_name = models.CharField(max_length=150, blank=True)
    order = models.PositiveSmallIntegerField(default=0)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.IN_PROGRESS)

    class Meta:
        ordering = ['order']

    def __str__(self):
        return f'{self.exercise_name} (session={self.session_id})'


class SetLog(models.Model):
    exercise_log = models.ForeignKey(ExerciseLog, on_delete=models.CASCADE, related_name='sets')
    set_number = models.PositiveSmallIntegerField()
    weight = models.FloatField()
    reps = models.PositiveSmallIntegerField()
    completed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['set_number']

    def __str__(self):
        return f'Set {self.set_number}: {self.weight}x{self.reps}'


class WorkoutFeedback(models.Model):
    class Difficulty(models.TextChoices):
        EASY = 'easy', 'Easy'
        GOOD = 'good', 'Good'
        HARD = 'hard', 'Hard'
        VERY_HARD = 'very_hard', 'Very Hard'

    session = models.OneToOneField(
        WorkoutSession, on_delete=models.CASCADE, related_name='feedback'
    )
    difficulty = models.CharField(max_length=16, choices=Difficulty.choices)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'Feedback(session={self.session_id}, difficulty={self.difficulty})'
