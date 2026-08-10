from ..models import PlannedExercise, WorkoutDay


class PlanEditError(Exception):
    pass


def _log_edit_note(user, text: str):
    from apps.adaptation.models import CoachingNote

    CoachingNote.objects.create(
        user=user, source=CoachingNote.Source.SYSTEM, text=text, category='exercise_selection'
    )


def add_exercise(day: WorkoutDay, *, exercise_name, target_sets, target_reps_min, target_reps_max,
                  rest_seconds, target_rir=None, order=None) -> PlannedExercise:
    if order is None:
        order = day.exercises.count()
    exercise = PlannedExercise.objects.create(
        day=day,
        order=order,
        exercise_name=exercise_name,
        target_sets=target_sets,
        target_reps_min=target_reps_min,
        target_reps_max=target_reps_max,
        rest_seconds=rest_seconds,
        target_rir=target_rir,
    )
    _log_edit_note(day.plan.user, f'Manually added "{exercise_name}" to their "{day.name}" day.')
    return exercise


def update_exercise(exercise: PlannedExercise, **fields) -> PlannedExercise:
    allowed = {'exercise_name', 'target_sets', 'target_reps_min', 'target_reps_max', 'rest_seconds', 'target_rir', 'order'}
    for key, value in fields.items():
        if key not in allowed:
            raise PlanEditError(f'Cannot update field "{key}".')
        setattr(exercise, key, value)
    exercise.save(update_fields=list(fields.keys()))
    return exercise


def remove_exercise(exercise: PlannedExercise):
    user = exercise.day.plan.user
    name = exercise.exercise_name
    day_name = exercise.day.name
    exercise.delete()
    _log_edit_note(user, f'Manually removed "{name}" from their "{day_name}" day.')


def reorder_exercises(day: WorkoutDay, ordered_exercise_ids: list[int]):
    exercises = {ex.id: ex for ex in day.exercises.all()}
    if set(ordered_exercise_ids) != set(exercises.keys()):
        raise PlanEditError('Reorder list must contain exactly this day\'s exercise ids.')
    for order, exercise_id in enumerate(ordered_exercise_ids):
        exercise = exercises[exercise_id]
        if exercise.order != order:
            exercise.order = order
            exercise.save(update_fields=['order'])
