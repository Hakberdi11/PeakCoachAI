from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

WORKOUT_DURATION_MIN = 15
WORKOUT_DURATION_MAX = 120


class OnboardingProfile(models.Model):
    class Goal(models.TextChoices):
        BUILD_MUSCLE = 'build_muscle', 'Build Muscle'
        LOSE_FAT = 'lose_fat', 'Lose Fat'
        INCREASE_STRENGTH = 'increase_strength', 'Increase Strength'
        IMPROVE_FITNESS = 'improve_fitness', 'Improve Fitness'
        BUILD_HABITS = 'build_habits', 'Build Healthy Habits'

    class Motivation(models.TextChoices):
        LOOKING_BETTER = 'looking_better', 'Looking Better'
        LIFTING_HEAVIER = 'lifting_heavier', 'Lifting Heavier'
        CONSISTENCY = 'consistency', 'Consistency'
        HEALTH = 'health', 'Health'
        ATHLETIC_PERFORMANCE = 'athletic_performance', 'Athletic Performance'

    class Experience(models.TextChoices):
        BEGINNER = 'beginner', 'Beginner'
        INTERMEDIATE = 'intermediate', 'Intermediate'
        ADVANCED = 'advanced', 'Advanced'

    class Gender(models.TextChoices):
        MALE = 'male', 'Male'
        FEMALE = 'female', 'Female'
        OTHER = 'other', 'Other'

    class TrainingEnvironment(models.TextChoices):
        COMMERCIAL_GYM = 'commercial_gym', 'Commercial Gym'
        HOME_GYM = 'home_gym', 'Home Gym'
        LIMITED_EQUIPMENT = 'limited_equipment', 'Limited Equipment'

    class CoachPersonality(models.TextChoices):
        DIRECT = 'direct', 'Direct'
        SUPPORTIVE = 'supportive', 'Supportive'
        BALANCED = 'balanced', 'Balanced'
        ADAPTIVE = 'adaptive', 'Adaptive'

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='onboarding_profile'
    )

    goal = models.CharField(max_length=32, choices=Goal.choices)
    motivation = models.CharField(max_length=32, choices=Motivation.choices)
    experience = models.CharField(max_length=32, choices=Experience.choices)

    age = models.PositiveSmallIntegerField()
    gender = models.CharField(max_length=16, choices=Gender.choices)
    height_cm = models.FloatField()
    weight_kg = models.FloatField()

    training_environment = models.CharField(max_length=32, choices=TrainingEnvironment.choices)
    equipment = models.JSONField(default=list, blank=True)

    training_days = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(2), MaxValueValidator(6)]
    )
    workout_duration = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(WORKOUT_DURATION_MIN), MaxValueValidator(WORKOUT_DURATION_MAX)]
    )
    priority_muscles = models.JSONField(default=list, blank=True)
    injuries = models.TextField(blank=True)
    coach_personality = models.CharField(max_length=32, choices=CoachPersonality.choices)

    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'OnboardingProfile(user={self.user_id})'
