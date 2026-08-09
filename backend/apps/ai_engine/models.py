from django.conf import settings
from django.db import models


class AIInsight(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='ai_insights'
    )
    text = models.CharField(max_length=280)
    category = models.CharField(max_length=32, default='general')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.text
