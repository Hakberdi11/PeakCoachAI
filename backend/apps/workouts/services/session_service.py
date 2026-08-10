from django.db.models import Q
from django.utils import timezone

from apps.progress.models import PersonalRecord

from ..models import ExerciseLog, PlannedExercise, SetLog, WorkoutSession
from .estimation import estimate_1rm


class SessionError(Exception):
    pass


def get_or_create_exercise_log(session: WorkoutSession, *, planned_exercise_id=None, exercise_name=None):
    planned_exercise = None
    if planned_exercise_id is not None:
        try:
            planned_exercise = PlannedExercise.objects.get(id=planned_exercise_id)
        except PlannedExercise.DoesNotExist as exc:
            raise SessionError('Planned exercise not found.') from exc

        log = session.exercise_logs.filter(planned_exercise=planned_exercise).first()
        if log:
            return log
        return ExerciseLog.objects.create(
            session=session,
            planned_exercise=planned_exercise,
            exercise_name=planned_exercise.exercise_name,
            order=planned_exercise.order,
        )

    if not exercise_name:
        raise SessionError('exercise_name is required when planned_exercise is not provided.')

    log = session.exercise_logs.filter(planned_exercise__isnull=True, exercise_name=exercise_name).first()
    if log:
        return log
    return ExerciseLog.objects.create(session=session, exercise_name=exercise_name)


def log_set(
    session: WorkoutSession,
    *,
    planned_exercise_id,
    exercise_name,
    set_number,
    weight,
    reps,
    rir=None,
    is_warmup=False,
):
    exercise_log = get_or_create_exercise_log(
        session, planned_exercise_id=planned_exercise_id, exercise_name=exercise_name
    )
    active_name = exercise_log.replaced_with_name or exercise_log.exercise_name

    # Computed before creating this set's row, so it naturally reflects everything
    # logged before now — including earlier sets in this same session. Matches on
    # either the original or replaced-with name so history carries across an
    # in-session exercise swap. Warmups are excluded and ranked by estimated 1RM
    # (not raw weight) so a low-rep near-max single doesn't automatically outrank
    # a heavier-effort higher-rep set.
    prior_sets = SetLog.objects.filter(
        exercise_log__session__user=session.user, is_warmup=False
    ).filter(Q(exercise_log__exercise_name=active_name) | Q(exercise_log__replaced_with_name=active_name))
    previous_best_e1rm = max((estimate_1rm(s.weight, s.reps) for s in prior_sets), default=None)

    set_log = SetLog.objects.create(
        exercise_log=exercise_log,
        set_number=set_number,
        weight=weight,
        reps=reps,
        rir=rir,
        is_warmup=is_warmup,
    )

    is_new_pr = False
    if not is_warmup and previous_best_e1rm is not None and estimate_1rm(weight, reps) > previous_best_e1rm:
        is_new_pr = True
        PersonalRecord.objects.create(
            user=session.user,
            exercise_name=active_name,
            weight=weight,
            reps=reps,
            session=session,
        )

    if exercise_log.status == ExerciseLog.Status.IN_PROGRESS:
        exercise_log.status = ExerciseLog.Status.COMPLETED
        exercise_log.save(update_fields=['status'])

    return exercise_log, set_log, is_new_pr


def skip_exercise(session: WorkoutSession, *, planned_exercise_id):
    exercise_log = get_or_create_exercise_log(session, planned_exercise_id=planned_exercise_id)
    exercise_log.status = ExerciseLog.Status.SKIPPED
    exercise_log.save(update_fields=['status'])
    return exercise_log


def replace_exercise(session: WorkoutSession, *, planned_exercise_id, new_exercise_name):
    exercise_log = get_or_create_exercise_log(session, planned_exercise_id=planned_exercise_id)
    exercise_log.status = ExerciseLog.Status.REPLACED
    exercise_log.replaced_with_name = new_exercise_name
    exercise_log.save(update_fields=['status', 'replaced_with_name'])
    return exercise_log


def finish_session(session: WorkoutSession):
    session.finished_at = timezone.now()
    session.status = WorkoutSession.Status.COMPLETED
    session.save(update_fields=['finished_at', 'status'])
    return session
