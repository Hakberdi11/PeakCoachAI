from rest_framework import serializers

from .models import (
    ExerciseLog,
    PlannedExercise,
    SetLog,
    WorkoutDay,
    WorkoutFeedback,
    WorkoutPlan,
    WorkoutSession,
)


class PlannedExerciseSerializer(serializers.ModelSerializer):
    class Meta:
        model = PlannedExercise
        fields = [
            'id', 'order', 'exercise_name', 'target_sets',
            'target_reps_min', 'target_reps_max', 'rest_seconds', 'notes',
        ]


class WorkoutDaySerializer(serializers.ModelSerializer):
    exercises = PlannedExerciseSerializer(many=True, read_only=True)

    class Meta:
        model = WorkoutDay
        fields = ['id', 'order', 'name', 'exercises']


class WorkoutPlanSerializer(serializers.ModelSerializer):
    days = WorkoutDaySerializer(many=True, read_only=True)

    class Meta:
        model = WorkoutPlan
        fields = ['id', 'created_at', 'is_active', 'source', 'days']


class SetLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = SetLog
        fields = ['id', 'set_number', 'weight', 'reps', 'completed_at']


class ExerciseLogSerializer(serializers.ModelSerializer):
    sets = SetLogSerializer(many=True, read_only=True)
    planned_exercise_id = serializers.IntegerField(source='planned_exercise.id', allow_null=True, read_only=True)

    class Meta:
        model = ExerciseLog
        fields = [
            'id', 'planned_exercise_id', 'exercise_name', 'replaced_with_name',
            'order', 'status', 'sets',
        ]


class WorkoutFeedbackSerializer(serializers.ModelSerializer):
    class Meta:
        model = WorkoutFeedback
        fields = ['difficulty', 'notes', 'created_at']


class WorkoutSessionSerializer(serializers.ModelSerializer):
    exercise_logs = ExerciseLogSerializer(many=True, read_only=True)
    feedback = WorkoutFeedbackSerializer(read_only=True)
    workout_day = WorkoutDaySerializer(read_only=True)

    class Meta:
        model = WorkoutSession
        fields = [
            'id', 'workout_day', 'started_at', 'finished_at', 'status',
            'exercise_logs', 'feedback',
        ]


class WorkoutSessionSummarySerializer(serializers.ModelSerializer):
    day_name = serializers.CharField(source='workout_day.name', default=None, read_only=True)

    class Meta:
        model = WorkoutSession
        fields = ['id', 'day_name', 'started_at', 'finished_at', 'status']
