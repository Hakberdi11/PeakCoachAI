from ..models import AdaptationHistory


def evaluate_reps(session):
    """Rule-based, per-exercise: repeated rep failures/overshoots adjust load next time."""
    decisions = []

    for log in session.exercise_logs.all():
        if log.status == 'skipped' or log.planned_exercise_id is None:
            continue

        sets = list(log.sets.all())
        if not sets:
            continue

        planned = log.planned_exercise
        active_name = log.replaced_with_name or log.exercise_name

        failed = sum(1 for s in sets if s.reps < planned.target_reps_min)
        exceeded_all = all(s.reps > planned.target_reps_max for s in sets)

        if failed >= 2:
            decisions.append(
                AdaptationHistory(
                    user=session.user,
                    workout_session=session,
                    exercise_name=active_name,
                    decision=AdaptationHistory.Decision.DECREASE_LOAD,
                    reason=f'Missed target reps in {failed} of {len(sets)} sets.',
                )
            )
        elif exceeded_all:
            decisions.append(
                AdaptationHistory(
                    user=session.user,
                    workout_session=session,
                    exercise_name=active_name,
                    decision=AdaptationHistory.Decision.INCREASE_LOAD,
                    reason='Exceeded target reps in every set.',
                )
            )

    AdaptationHistory.objects.bulk_create(decisions)
    return decisions


def evaluate_feedback(session, feedback):
    """Session-level: repeated hard/very-hard feedback lowers next plan's volume."""
    from apps.workouts.models import WorkoutFeedback

    recent = list(
        WorkoutFeedback.objects.filter(session__user=session.user)
        .order_by('-created_at')[:3]
    )
    hard_count = sum(1 for f in recent if f.difficulty in ('hard', 'very_hard'))

    if len(recent) >= 2 and hard_count == len(recent):
        return AdaptationHistory.objects.create(
            user=session.user,
            workout_session=session,
            exercise_name='',
            decision=AdaptationHistory.Decision.DECREASE_VOLUME,
            reason=f'Last {len(recent)} workouts rated hard or very hard.',
        )
    return None
