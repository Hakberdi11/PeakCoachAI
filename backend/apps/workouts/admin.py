from django.contrib import admin

from .models import (
    ExerciseLog,
    PlannedExercise,
    SetLog,
    WorkoutDay,
    WorkoutFeedback,
    WorkoutPlan,
    WorkoutSession,
)

admin.site.register(WorkoutPlan)
admin.site.register(WorkoutDay)
admin.site.register(PlannedExercise)
admin.site.register(WorkoutSession)
admin.site.register(ExerciseLog)
admin.site.register(SetLog)
admin.site.register(WorkoutFeedback)
