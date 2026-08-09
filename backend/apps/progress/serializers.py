from rest_framework import serializers

from .models import PersonalRecord


class PersonalRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = PersonalRecord
        fields = ['id', 'exercise_name', 'weight', 'reps', 'achieved_at']
