import json

from django.db import transaction

from apps.ai_engine.services.openai_provider import OpenAIProvider
from apps.onboarding.models import OnboardingProfile

from ..models import PlannedExercise, WorkoutDay, WorkoutPlan
from .prescription import Prescription, compute_prescription, validate_against_prescription

_SCHEMA_INSTRUCTIONS = """
This schema only supports rep-based exercises — do not include isometric holds or
time-based exercises (e.g. planks, farmer's carries, wall sits) since there is no
duration field. Choose a rep-based substitute for core/conditioning work instead
(e.g. sit-ups, leg raises, crunches instead of planks).

Respond with ONLY a JSON object matching this exact schema, no prose:
{
  "days": [
    {
      "name": "string, e.g. 'Push' or 'Full Body'",
      "exercises": [
        {
          "name": "string",
          "sets": integer,
          "reps_min": integer,
          "reps_max": integer,
          "rest_seconds": integer,
          "target_rir": integer,
          "order": integer
        }
      ]
    }
  ]
}
"""


class PlanGenerationError(Exception):
    pass


def _format_adaptation_notes(adaptation_history) -> str:
    if not adaptation_history:
        return ''

    lines = '\n'.join(f'- {a.exercise_name or "Overall"}: {a.decision} — {a.reason}' for a in adaptation_history)
    return f"""
This athlete has trained with you before. Recent coaching adjustments to account for:
{lines}
Apply these adjustments where relevant (e.g. reduce load/volume for flagged exercises, increase
challenge where the athlete has been exceeding targets).
"""


def _build_prompt(profile: OnboardingProfile, prescription: Prescription, adaptation_history=None) -> str:
    return f"""
You are an expert strength and conditioning coach designing a personalized workout program.

Athlete profile:
- Goal: {profile.get_goal_display()}
- Motivation: {profile.get_motivation_display()}
- Experience: {profile.get_experience_display()}
- Age: {profile.age}, Gender: {profile.get_gender_display()}
- Height: {profile.height_cm}cm, Weight: {profile.weight_kg}kg
- Training environment: {profile.get_training_environment_display()}
- Available equipment: {', '.join(profile.equipment) or 'bodyweight only'}
- Training days per week: {profile.training_days}
- Workout duration target: {profile.workout_duration} minutes
- Priority muscles: {', '.join(profile.priority_muscles) or 'none specified'}
- Injuries / limitations: {profile.injuries or 'none reported'}
{prescription.as_prompt_block()}
{_format_adaptation_notes(adaptation_history)}
Design a training split with exactly {profile.training_days} training days that fits within the
workout duration and uses only the available equipment. Respect injuries/limitations by avoiding
contraindicated movements. Prioritize the athlete's priority muscles without neglecting balance.

{_SCHEMA_INSTRUCTIONS}
"""


def _build_revision_prompt(
    profile: OnboardingProfile, prescription: Prescription, current_plan: dict, instruction: str
) -> str:
    return f"""
You are an expert strength and conditioning coach. This athlete already has the following workout
plan and wants you to revise it based on their instruction below. Keep everything that isn't
affected by the instruction the same — this is a targeted revision, not a fresh redesign.

Current plan (JSON):
{json.dumps(current_plan)}

Athlete's requested change:
"{instruction}"

Athlete profile for context:
- Goal: {profile.get_goal_display()}, Experience: {profile.get_experience_display()}
- Available equipment: {', '.join(profile.equipment) or 'bodyweight only'}
- Injuries / limitations: {profile.injuries or 'none reported'}
{prescription.as_prompt_block()}
This schema only supports rep-based exercises — no isometric holds or time-based exercises
(e.g. planks, wall sits), since there is no duration field. Use a rep-based substitute instead.

Respond with ONLY a JSON object matching this exact schema, no prose:
{{
  "change_summary": "one short sentence describing what you changed and why",
  "days": [
    {{
      "name": "string",
      "exercises": [
        {{"name": "string", "sets": integer, "reps_min": integer, "reps_max": integer,
          "rest_seconds": integer, "target_rir": integer, "order": integer}}
      ]
    }}
  ]
}}
"""


def _to_display_shape(raw: dict) -> dict:
    """Converts the AI's schema (name/sets/reps_min/reps_max) into the API's
    display shape (exercise_name/target_sets/target_reps_min/target_reps_max),
    shared by both the anonymous preview response and the persisted plan."""
    return {
        'days': [
            {
                'name': day['name'],
                'exercises': [
                    {
                        'order': exercise.get('order', index),
                        'exercise_name': exercise['name'],
                        'target_sets': exercise['sets'],
                        'target_reps_min': exercise['reps_min'],
                        'target_reps_max': exercise['reps_max'],
                        'rest_seconds': exercise['rest_seconds'],
                        'target_rir': exercise.get('target_rir'),
                    }
                    for index, exercise in enumerate(day['exercises'])
                ],
            }
            for day in raw['days']
        ]
    }


class WorkoutPlanGenerator:
    def __init__(self, ai_provider=None):
        self.ai_provider = ai_provider or OpenAIProvider()

    def generate_preview(self, profile_data: dict) -> dict:
        """Generates a plan from raw onboarding answers without touching the database.
        Used for the pre-signup 'see your plan' preview."""
        profile = OnboardingProfile(**profile_data)
        return self.generate_preview_from_profile(profile)

    def generate_preview_from_profile(self, profile: OnboardingProfile, adaptation_history=None, coaching_notes=None) -> dict:
        prescription = compute_prescription(profile, coaching_notes)
        prompt = _build_prompt(profile, prescription, adaptation_history)
        raw = self._generate_and_parse(prompt, prescription)
        return _to_display_shape(raw)

    def generate(self, user) -> WorkoutPlan:
        """Generates and persists a plan for a user who has already completed onboarding,
        taking into account any adaptation decisions and stated preferences from their history."""
        try:
            profile = OnboardingProfile.objects.get(user=user)
        except OnboardingProfile.DoesNotExist as exc:
            raise PlanGenerationError('Onboarding must be completed before generating a plan.') from exc

        from apps.adaptation.models import AdaptationHistory, CoachingNote

        adaptation_history = AdaptationHistory.objects.filter(user=user)[:10]
        coaching_notes = CoachingNote.objects.filter(user=user)[:20]

        display_plan = self.generate_preview_from_profile(profile, adaptation_history, coaching_notes)
        return self.persist(user, display_plan)

    def revise(self, user, instruction: str) -> tuple[WorkoutPlan, str]:
        """Revises the user's active plan per a free-text instruction, and records
        the instruction as a CoachingNote so it's honored on future generations too."""
        from apps.adaptation.models import CoachingNote

        try:
            profile = OnboardingProfile.objects.get(user=user)
        except OnboardingProfile.DoesNotExist as exc:
            raise PlanGenerationError('Onboarding must be completed before revising a plan.') from exc

        current_plan = WorkoutPlan.objects.filter(user=user, is_active=True).first()
        if current_plan is None:
            raise PlanGenerationError('No active plan to revise.')

        current_display = WorkoutPlanGenerator._plan_to_display_shape(current_plan)
        prescription = compute_prescription(profile, CoachingNote.objects.filter(user=user)[:20])
        prompt = _build_revision_prompt(profile, prescription, current_display, instruction)

        raw = self._generate_and_parse(prompt, prescription, has_change_summary=True)
        change_summary = raw.get('change_summary', '')
        display_plan = _to_display_shape(raw)

        plan = self.persist(user, display_plan)
        CoachingNote.objects.create(user=user, source=CoachingNote.Source.USER, text=instruction)
        return plan, change_summary

    @staticmethod
    def _plan_to_display_shape(plan: WorkoutPlan) -> dict:
        return {
            'days': [
                {
                    'name': day.name,
                    'exercises': [
                        {
                            'order': ex.order,
                            'exercise_name': ex.exercise_name,
                            'target_sets': ex.target_sets,
                            'target_reps_min': ex.target_reps_min,
                            'target_reps_max': ex.target_reps_max,
                            'rest_seconds': ex.rest_seconds,
                            'target_rir': ex.target_rir,
                        }
                        for ex in day.exercises.all()
                    ],
                }
                for day in plan.days.all()
            ]
        }

    def persist(self, user, display_plan: dict) -> WorkoutPlan:
        """Persists an already-generated plan (in display shape) for a user.
        Used by generate(), revise(), and to save a plan the user already previewed
        pre-signup. Validated against the user's own prescription envelope so a
        client can't submit an arbitrary out-of-range plan via save-preview."""
        try:
            profile = OnboardingProfile.objects.get(user=user)
        except OnboardingProfile.DoesNotExist as exc:
            raise PlanGenerationError('Onboarding must be completed before saving a plan.') from exc

        prescription = compute_prescription(profile)
        is_valid, error = validate_against_prescription(display_plan, prescription)
        if not is_valid:
            raise PlanGenerationError(f'Invalid workout plan payload: {error}')

        with transaction.atomic():
            WorkoutPlan.objects.filter(user=user, is_active=True).update(is_active=False)
            plan = WorkoutPlan.objects.create(user=user, source='ai', raw_ai_response=display_plan)

            for day_order, day_data in enumerate(display_plan['days']):
                day = WorkoutDay.objects.create(
                    plan=plan, order=day_order, name=day_data['name']
                )
                for exercise_data in day_data['exercises']:
                    PlannedExercise.objects.create(
                        day=day,
                        order=exercise_data.get('order', 0),
                        exercise_name=exercise_data['exercise_name'],
                        target_sets=exercise_data['target_sets'],
                        target_reps_min=exercise_data['target_reps_min'],
                        target_reps_max=exercise_data['target_reps_max'],
                        rest_seconds=exercise_data['rest_seconds'],
                        target_rir=exercise_data.get('target_rir'),
                    )

        return plan

    def _generate_and_parse(self, prompt: str, prescription: Prescription, has_change_summary: bool = False) -> dict:
        raw = self.ai_provider.generate_completion(prompt)
        parsed = self._try_parse(raw, has_change_summary)
        if parsed is not None and self._within_prescription(parsed, prescription):
            return parsed

        retry_prompt = (
            f'{prompt}\n\nYour previous response was not valid JSON matching the schema, or did not '
            'respect the numeric prescription bounds given above. Respond again with ONLY the raw '
            'JSON object, no markdown fences, no commentary, and stay strictly within the given '
            'sets/reps/rest/RIR/exercise-count ranges.'
        )
        raw_retry = self.ai_provider.generate_completion(retry_prompt)
        parsed_retry = self._try_parse(raw_retry, has_change_summary)
        if parsed_retry is not None and self._within_prescription(parsed_retry, prescription):
            return parsed_retry

        raise PlanGenerationError('AI provider did not return a valid workout plan.')

    @staticmethod
    def _within_prescription(parsed: dict, prescription: Prescription) -> bool:
        display_shape = _to_display_shape(parsed)
        is_valid, _ = validate_against_prescription(display_shape, prescription)
        return is_valid

    @staticmethod
    def _try_parse(raw: str, has_change_summary: bool = False) -> dict | None:
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            return None

        if not isinstance(data, dict) or 'days' not in data or not isinstance(data['days'], list):
            return None
        if has_change_summary and 'change_summary' not in data:
            return None

        for day in data['days']:
            if 'name' not in day or 'exercises' not in day:
                return None
            for exercise in day['exercises']:
                required = {'name', 'sets', 'reps_min', 'reps_max', 'rest_seconds'}
                if not required.issubset(exercise.keys()):
                    return None

        return data
