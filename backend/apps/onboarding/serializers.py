from rest_framework import serializers

from .models import OnboardingProfile


class OnboardingProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = OnboardingProfile
        fields = [
            'goal', 'motivation', 'experience',
            'age', 'gender', 'height_cm', 'weight_kg',
            'training_environment', 'equipment',
            'training_days', 'workout_duration',
            'priority_muscles', 'injuries', 'coach_personality',
            'completed_at',
        ]
        read_only_fields = ['completed_at']
