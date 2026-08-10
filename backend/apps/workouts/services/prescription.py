"""Deterministic prescription layer.

Turns an onboarding profile into a numeric training envelope — exercise count,
sets, rep range, rest, target RIR — *before* the AI is asked to design a plan.
The AI's job narrows to exercise selection within these bounds instead of
inventing session structure from scratch, which is what let a 60-minute,
3-year-experience, commercial-gym session come back as five exercises.

Numeric brackets are sourced from docs/research/<goal>-findings.md; see that
report for the underlying evidence and confidence grading behind each range.
"""

from dataclasses import dataclass

from apps.onboarding.models import OnboardingProfile

# Rough seconds of active work per set, used to size exercise count against
# the athlete's stated session length so we don't overfill or underfill it.
_SECONDS_PER_SET_WORK = 40
_MIN_EXERCISES_PER_DAY = 3
_MAX_EXERCISES_PER_DAY = 9


@dataclass(frozen=True)
class Prescription:
    goal: str
    experience: str
    exercises_per_day: tuple[int, int]
    sets: tuple[int, int]
    reps: tuple[int, int]
    rest_seconds: tuple[int, int]
    rir: tuple[int, int]
    weekly_sets_per_muscle: tuple[int, int]
    guidance: str

    def as_prompt_block(self) -> str:
        return f"""
Numeric prescription for this athlete (computed from their profile — respect these bounds,
do not invent your own set/rep/rest numbers outside them):
- Exercises per training day: {self.exercises_per_day[0]}-{self.exercises_per_day[1]}
- Sets per exercise: {self.sets[0]}-{self.sets[1]}
- Rep range: {self.reps[0]}-{self.reps[1]}
- Rest between sets: {self.rest_seconds[0]}-{self.rest_seconds[1]} seconds
- Target RIR (reps in reserve) at top sets: {self.rir[0]}-{self.rir[1]}
- Target weekly sets per trained muscle group, summed across the week's days: {self.weekly_sets_per_muscle[0]}-{self.weekly_sets_per_muscle[1]}
{self.guidance}
Every exercise's "sets", "reps_min"/"reps_max", "rest_seconds", and "target_rir" fields must fall
within the ranges above. Choose exercise count per day within the given range so the session
realistically fills the athlete's stated workout duration without running over.
"""


# goal -> experience -> base numeric envelope. `weekly_sets_per_muscle` is a
# research-backed ballpark used only as guidance text for the AI's split
# design; it isn't validated per-exercise since it depends on how muscles are
# distributed across days.
_ENVELOPES: dict[str, dict[str, dict]] = {
    OnboardingProfile.Goal.BUILD_MUSCLE: {
        'beginner': dict(sets=(3, 3), reps=(8, 12), rest=(60, 90), rir=(2, 3), weekly=(8, 12)),
        'intermediate': dict(sets=(3, 4), reps=(6, 12), rest=(60, 120), rir=(1, 3), weekly=(12, 16)),
        'advanced': dict(sets=(4, 5), reps=(6, 15), rest=(60, 120), rir=(0, 2), weekly=(16, 20)),
    },
    OnboardingProfile.Goal.INCREASE_STRENGTH: {
        # Reps are widened beyond the primary-lift target (stated in guidance)
        # to leave room for accessory work at higher reps within the same day
        # — a real strength session isn't 1-5 reps on every exercise.
        'beginner': dict(sets=(3, 4), reps=(5, 12), rest=(120, 180), rir=(2, 3), weekly=(6, 8)),
        'intermediate': dict(sets=(3, 5), reps=(3, 12), rest=(150, 240), rir=(1, 3), weekly=(8, 10)),
        'advanced': dict(sets=(4, 5), reps=(1, 15), rest=(180, 300), rir=(0, 2), weekly=(8, 12)),
    },
    OnboardingProfile.Goal.LOSE_FAT: {
        'beginner': dict(sets=(3, 3), reps=(10, 15), rest=(60, 90), rir=(2, 3), weekly=(6, 10)),
        'intermediate': dict(sets=(3, 3), reps=(8, 15), rest=(60, 90), rir=(2, 3), weekly=(8, 12)),
        'advanced': dict(sets=(3, 4), reps=(8, 15), rest=(60, 90), rir=(1, 3), weekly=(10, 14)),
    },
    OnboardingProfile.Goal.IMPROVE_FITNESS: {
        'beginner': dict(sets=(1, 2), reps=(10, 15), rest=(60, 90), rir=(3, 4), weekly=(4, 8)),
        'intermediate': dict(sets=(2, 3), reps=(8, 15), rest=(60, 90), rir=(2, 4), weekly=(6, 10)),
        'advanced': dict(sets=(2, 3), reps=(8, 15), rest=(60, 90), rir=(2, 3), weekly=(6, 10)),
    },
    OnboardingProfile.Goal.BUILD_HABITS: {
        'beginner': dict(sets=(2, 3), reps=(8, 12), rest=(60, 90), rir=(3, 4), weekly=(4, 8)),
        'intermediate': dict(sets=(2, 3), reps=(8, 15), rest=(60, 90), rir=(2, 4), weekly=(6, 10)),
        'advanced': dict(sets=(2, 3), reps=(8, 15), rest=(60, 90), rir=(2, 4), weekly=(6, 10)),
    },
}

_GUIDANCE: dict[str, str] = {
    OnboardingProfile.Goal.BUILD_MUSCLE: (
        'Prioritize the athlete\'s priority muscles by giving them more exercises/sets within the '
        'weekly range above, without dropping other muscle groups to zero.'
    ),
    OnboardingProfile.Goal.INCREASE_STRENGTH: (
        'Build the split around the primary barbell/compound lifts available in the athlete\'s '
        'equipment, and keep those main lifts at the low end of the rep range above (close to the '
        'minimum, near the target RIR). Accessory work can run higher in the rep range (up to the '
        'stated maximum) and does not need to hit the same RIR floor as the main lifts.'
    ),
    OnboardingProfile.Goal.LOSE_FAT: (
        'This athlete is likely in a calorie deficit. Do not chase near-failure sets on every exercise '
        '(protect recovery capacity) and favor exercises with low technical/joint cost across a longer '
        'session. Prefer keeping load stimulus intact over adding volume.'
    ),
    OnboardingProfile.Goal.IMPROVE_FITNESS: (
        'This is a general-health dose, not a maximal hypertrophy or strength program — favor full-body '
        'or upper/lower coverage over narrow body-part splits, and keep intensity comfortably submaximal.'
    ),
    OnboardingProfile.Goal.BUILD_HABITS: (
        'Deliberately keep this session easier than what looks "optimal" — the goal is a session the '
        'athlete will actually repeat, not the biggest possible stimulus. Favor simple, low-setup '
        'exercises and protect the athlete\'s stated training days over chasing intensity.'
    ),
}


def _estimate_exercise_count(workout_duration_minutes: int, sets_range: tuple[int, int], rest_range: tuple[int, int]) -> tuple[int, int]:
    sets_mid = sum(sets_range) / 2
    rest_mid = sum(rest_range) / 2
    seconds_per_set = _SECONDS_PER_SET_WORK + rest_mid
    total_seconds = workout_duration_minutes * 60
    exercises_mid = total_seconds / (sets_mid * seconds_per_set)
    # Deliberately wide band: this is a derived scheduling heuristic, not a
    # directly-researched number like sets/reps/rest, and real sessions vary a
    # lot with equipment transitions and warm-ups. Its job is only to rule out
    # degenerate cases (a 45-minute session with 2 exercises), not to pin an
    # exact count.
    low = max(_MIN_EXERCISES_PER_DAY, round(exercises_mid * 0.55))
    high = min(_MAX_EXERCISES_PER_DAY, max(low + 1, round(exercises_mid * 1.15)))
    return (low, high)


def compute_prescription(profile: OnboardingProfile, coaching_notes=None) -> Prescription:
    goal = profile.goal
    experience = profile.experience
    envelope = _ENVELOPES.get(goal, _ENVELOPES[OnboardingProfile.Goal.BUILD_MUSCLE]).get(
        experience, _ENVELOPES.get(goal, _ENVELOPES[OnboardingProfile.Goal.BUILD_MUSCLE])['intermediate']
    )

    exercises_per_day = _estimate_exercise_count(profile.workout_duration, envelope['sets'], envelope['rest'])

    guidance_parts = [_GUIDANCE.get(goal, '')]
    if coaching_notes:
        notes_text = '\n'.join(f'- {note.text}' for note in coaching_notes)
        guidance_parts.append(
            f'The athlete has previously told their coach the following — weigh these preferences '
            f'when choosing exercises and adjusting within the ranges above:\n{notes_text}'
        )

    return Prescription(
        goal=goal,
        experience=experience,
        exercises_per_day=exercises_per_day,
        sets=envelope['sets'],
        reps=envelope['reps'],
        rest_seconds=envelope['rest'],
        rir=envelope['rir'],
        weekly_sets_per_muscle=envelope['weekly'],
        guidance='\n'.join(p for p in guidance_parts if p),
    )


def validate_against_prescription(display_plan: dict, prescription: Prescription) -> tuple[bool, str]:
    """Structural + bounds validation of the AI's (or a client-submitted) plan
    against the computed envelope. Returns (is_valid, error_message)."""
    if not isinstance(display_plan, dict) or not isinstance(display_plan.get('days'), list) or not display_plan['days']:
        return False, 'Plan must contain a non-empty list of days.'

    sets_lo, sets_hi = prescription.sets
    reps_lo, reps_hi = prescription.reps
    rest_lo, rest_hi = prescription.rest_seconds
    ex_lo, ex_hi = prescription.exercises_per_day
    # Give the AI/edit flow a little slack around the computed bounds rather
    # than hard-rejecting a plan that's off by one set or a few seconds of rest.
    sets_lo, sets_hi = max(1, sets_lo - 1), sets_hi + 1
    reps_lo, reps_hi = max(1, reps_lo - 2), reps_hi + 4
    rest_lo, rest_hi = max(15, rest_lo - 30), rest_hi + 60
    ex_lo, ex_hi = max(1, ex_lo - 1), ex_hi + 2

    for day in display_plan['days']:
        if 'name' not in day or not isinstance(day.get('exercises'), list) or not day['exercises']:
            return False, f'Day "{day.get("name", "?")}" must have a name and at least one exercise.'
        if not (ex_lo <= len(day['exercises']) <= ex_hi):
            return False, (
                f'Day "{day["name"]}" has {len(day["exercises"])} exercises, expected '
                f'{ex_lo}-{ex_hi} for this athlete\'s duration/experience.'
            )
        for exercise in day['exercises']:
            required = {'exercise_name', 'target_sets', 'target_reps_min', 'target_reps_max', 'rest_seconds'}
            if not required.issubset(exercise.keys()):
                return False, f'Exercise {exercise} is missing required fields.'
            if not (sets_lo <= exercise['target_sets'] <= sets_hi):
                return False, f'{exercise["exercise_name"]}: target_sets out of range.'
            if not (reps_lo <= exercise['target_reps_min'] <= exercise['target_reps_max'] <= reps_hi):
                return False, f'{exercise["exercise_name"]}: rep range out of bounds.'
            if not (rest_lo <= exercise['rest_seconds'] <= rest_hi):
                return False, f'{exercise["exercise_name"]}: rest_seconds out of bounds.'

    return True, ''
