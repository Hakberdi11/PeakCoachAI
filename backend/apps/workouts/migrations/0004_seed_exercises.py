from django.db import migrations

# (name, muscle_group, equipment_needed) — equipment_needed values match the
# onboarding equipment choices in OnboardingProfile.equipment / the frontend's
# _equipmentOptions; [] means bodyweight-only.
EXERCISES = [
    # Chest
    ('Barbell Bench Press', 'chest', ['barbell']),
    ('Incline Barbell Bench Press', 'chest', ['barbell']),
    ('Dumbbell Bench Press', 'chest', ['dumbbells']),
    ('Incline Dumbbell Press', 'chest', ['dumbbells']),
    ('Dumbbell Fly', 'chest', ['dumbbells']),
    ('Cable Chest Fly', 'chest', ['cables']),
    ('Chest Press Machine', 'chest', ['machines']),
    ('Pec Deck Machine', 'chest', ['machines']),
    ('Push-Up', 'chest', []),
    ('Incline Push-Up', 'chest', []),
    ('Dips', 'chest', []),
    ('Resistance Band Chest Press', 'chest', ['resistance_bands']),
    # Back
    ('Deadlift', 'back', ['barbell']),
    ('Barbell Row', 'back', ['barbell']),
    ('Pull-Up', 'back', ['pull_up_bar']),
    ('Chin-Up', 'back', ['pull_up_bar']),
    ('Lat Pulldown', 'back', ['cables']),
    ('Seated Cable Row', 'back', ['cables']),
    ('Dumbbell Row', 'back', ['dumbbells']),
    ('T-Bar Row', 'back', ['barbell']),
    ('Back Extension', 'back', []),
    ('Resistance Band Row', 'back', ['resistance_bands']),
    ('Assisted Pull-Up Machine', 'back', ['machines']),
    ('Row Machine', 'back', ['machines']),
    # Shoulders
    ('Overhead Barbell Press', 'shoulders', ['barbell']),
    ('Seated Dumbbell Shoulder Press', 'shoulders', ['dumbbells']),
    ('Lateral Raise', 'shoulders', ['dumbbells']),
    ('Cable Lateral Raise', 'shoulders', ['cables']),
    ('Front Raise', 'shoulders', ['dumbbells']),
    ('Rear Delt Fly', 'shoulders', ['dumbbells']),
    ('Face Pull', 'shoulders', ['cables']),
    ('Shoulder Press Machine', 'shoulders', ['machines']),
    ('Pike Push-Up', 'shoulders', []),
    ('Resistance Band Lateral Raise', 'shoulders', ['resistance_bands']),
    # Arms
    ('Barbell Curl', 'arms', ['barbell']),
    ('Dumbbell Curl', 'arms', ['dumbbells']),
    ('Hammer Curl', 'arms', ['dumbbells']),
    ('Cable Curl', 'arms', ['cables']),
    ('Preacher Curl', 'arms', ['barbell']),
    ('Close-Grip Bench Press', 'arms', ['barbell']),
    ('Triceps Pushdown', 'arms', ['cables']),
    ('Overhead Triceps Extension', 'arms', ['dumbbells']),
    ('Dumbbell Skull Crusher', 'arms', ['dumbbells']),
    ('Bench Dip', 'arms', []),
    ('Diamond Push-Up', 'arms', []),
    ('Resistance Band Curl', 'arms', ['resistance_bands']),
    # Legs
    ('Barbell Back Squat', 'legs', ['barbell']),
    ('Barbell Front Squat', 'legs', ['barbell']),
    ('Romanian Deadlift', 'legs', ['barbell']),
    ('Leg Press', 'legs', ['machines']),
    ('Leg Extension', 'legs', ['machines']),
    ('Leg Curl', 'legs', ['machines']),
    ('Walking Lunge', 'legs', ['dumbbells']),
    ('Bulgarian Split Squat', 'legs', ['dumbbells']),
    ('Goblet Squat', 'legs', ['dumbbells']),
    ('Hip Thrust', 'legs', ['barbell']),
    ('Standing Calf Raise', 'legs', ['machines']),
    ('Bodyweight Squat', 'legs', []),
    ('Glute Bridge', 'legs', []),
    ('Step-Up', 'legs', ['dumbbells']),
    ('Resistance Band Squat', 'legs', ['resistance_bands']),
    # Core
    ('Plank', 'core', []),
    ('Side Plank', 'core', []),
    ('Hanging Leg Raise', 'core', ['pull_up_bar']),
    ('Cable Crunch', 'core', ['cables']),
    ('Russian Twist', 'core', ['dumbbells']),
    ('Ab Wheel Rollout', 'core', []),
    ('Bicycle Crunch', 'core', []),
    ('Mountain Climber', 'core', []),
    ('Weighted Sit-Up', 'core', ['dumbbells']),
    # Full body / conditioning
    ('Kettlebell Swing', 'full_body', ['dumbbells']),
    ('Burpee', 'full_body', []),
    ('Jump Rope', 'full_body', []),
    ('Rowing Machine', 'full_body', ['machines']),
    ('Battle Ropes', 'full_body', ['machines']),
    ('Farmer\'s Carry', 'full_body', ['dumbbells']),
]


def seed_exercises(apps, schema_editor):
    Exercise = apps.get_model('workouts', 'Exercise')
    Exercise.objects.bulk_create(
        [
            Exercise(name=name, muscle_group=muscle_group, equipment_needed=equipment)
            for name, muscle_group, equipment in EXERCISES
        ],
        ignore_conflicts=True,
    )


def unseed_exercises(apps, schema_editor):
    Exercise = apps.get_model('workouts', 'Exercise')
    Exercise.objects.filter(name__in=[name for name, _, _ in EXERCISES]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ('workouts', '0003_exercise_plannedexercise_target_rir_setlog_is_warmup_and_more'),
    ]

    operations = [
        migrations.RunPython(seed_exercises, unseed_exercises),
    ]
