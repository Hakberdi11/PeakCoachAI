from django.contrib import admin

from .models import PersonalRecord, WorkoutStreak

admin.site.register(PersonalRecord)
admin.site.register(WorkoutStreak)
