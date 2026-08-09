from rest_framework import serializers

from .models import AIInsight


class AIInsightSerializer(serializers.ModelSerializer):
    class Meta:
        model = AIInsight
        fields = ['id', 'text', 'category', 'created_at']
