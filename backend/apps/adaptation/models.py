from django.conf import settings
from django.db import models


class AdaptationHistory(models.Model):
    class Decision(models.TextChoices):
        INCREASE_LOAD = 'increase_load', 'Increase Load'
        DECREASE_LOAD = 'decrease_load', 'Decrease Load'
        DECREASE_VOLUME = 'decrease_volume', 'Decrease Volume'
        MAINTAIN = 'maintain', 'Maintain'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='adaptation_history'
    )
    workout_session = models.ForeignKey(
        'workouts.WorkoutSession', on_delete=models.CASCADE, related_name='adaptation_decisions'
    )
    exercise_name = models.CharField(max_length=150, blank=True)
    decision = models.CharField(max_length=32, choices=Decision.choices)
    reason = models.CharField(max_length=255)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name_plural = 'adaptation history'

    def __str__(self):
        return f'{self.decision} for {self.exercise_name or "session"} (user={self.user_id})'


class CoachingNote(models.Model):
    """Freeform accumulated preference/feedback, distinct from AdaptationHistory's
    structured per-session decisions. Written from user-issued plan-revision
    instructions (source='user') or auto-summarized from manual plan edits
    (source='system'), and folded into every future plan generation/revision
    prompt so stated preferences persist across sessions."""

    class Source(models.TextChoices):
        USER = 'user', 'User'
        SYSTEM = 'system', 'System'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='coaching_notes'
    )
    source = models.CharField(max_length=16, choices=Source.choices)
    text = models.TextField()
    category = models.CharField(max_length=32, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'CoachingNote({self.source}, user={self.user_id})'
