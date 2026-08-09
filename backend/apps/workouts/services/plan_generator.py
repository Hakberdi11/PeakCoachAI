import json

from django.db import transaction

from apps.ai_engine.services.openai_provider import OpenAIProvider
from apps.onboarding.models import OnboardingProfile

from ..models import PlannedExercise, WorkoutDay, WorkoutPlan

_SCHEMA_INSTRUCTIONS = """
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


def _build_prompt(profile: OnboardingProfile, adaptation_history=None) -> str:
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
- Training style: {profile.get_training_style_display()}
- Priority muscles: {', '.join(profile.priority_muscles) or 'none specified'}
- Injuries / limitations: {profile.injuries or 'none reported'}
{_format_adaptation_notes(adaptation_history)}
Design a training split with exactly {profile.training_days} training days that fits within the
workout duration and uses only the available equipment. Respect injuries/limitations by avoiding
contraindicated movements. Prioritize the athlete's priority muscles without neglecting balance.

{_SCHEMA_INSTRUCTIONS}
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
                        'rest_seconds': exercise.get('rest_seconds', 90),
                    }
                    for index, exercise in enumerate(day['exercises'])
                ],
            }
            for day in raw['days']
        ]
    }


def _validate_display_shape(data) -> bool:
    if not isinstance(data, dict) or not isinstance(data.get('days'), list):
        return False
    for day in data['days']:
        if 'name' not in day or not isinstance(day.get('exercises'), list):
            return False
        required = {'exercise_name', 'target_sets', 'target_reps_min', 'target_reps_max'}
        for exercise in day['exercises']:
            if not required.issubset(exercise.keys()):
                return False
    return True


class WorkoutPlanGenerator:
    def __init__(self, ai_provider=None):
        self.ai_provider = ai_provider or OpenAIProvider()

    def generate_preview(self, profile_data: dict) -> dict:
        """Generates a plan from raw onboarding answers without touching the database.
        Used for the pre-signup 'see your plan' preview."""
        profile = OnboardingProfile(**profile_data)
        return self.generate_preview_from_profile(profile)

    def generate_preview_from_profile(self, profile: OnboardingProfile, adaptation_history=None) -> dict:
        prompt = _build_prompt(profile, adaptation_history)
        raw = self._generate_and_parse(prompt)
        return _to_display_shape(raw)

    def generate(self, user) -> WorkoutPlan:
        """Generates and persists a plan for a user who has already completed onboarding,
        taking into account any adaptation decisions from their training history."""
        try:
            profile = OnboardingProfile.objects.get(user=user)
        except OnboardingProfile.DoesNotExist as exc:
            raise PlanGenerationError('Onboarding must be completed before generating a plan.') from exc

        from apps.adaptation.models import AdaptationHistory

        adaptation_history = AdaptationHistory.objects.filter(user=user)[:10]

        display_plan = self.generate_preview_from_profile(profile, adaptation_history)
        return self.persist(user, display_plan)

    def persist(self, user, display_plan: dict) -> WorkoutPlan:
        """Persists an already-generated plan (in display shape) for a user.
        Used both by generate() and to save a plan the user already previewed pre-signup."""
        if not _validate_display_shape(display_plan):
            raise PlanGenerationError('Invalid workout plan payload.')

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
                        rest_seconds=exercise_data.get('rest_seconds', 90),
                    )

        return plan

    def _generate_and_parse(self, prompt: str) -> dict:
        raw = self.ai_provider.generate_completion(prompt)
        parsed = self._try_parse(raw)
        if parsed is not None:
            return parsed

        retry_prompt = (
            f'{prompt}\n\nYour previous response was not valid JSON matching the schema. '
            'Respond again with ONLY the raw JSON object, no markdown fences, no commentary.'
        )
        raw_retry = self.ai_provider.generate_completion(retry_prompt)
        parsed_retry = self._try_parse(raw_retry)
        if parsed_retry is not None:
            return parsed_retry

        raise PlanGenerationError('AI provider did not return a valid workout plan.')

    @staticmethod
    def _try_parse(raw: str) -> dict | None:
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            return None

        if not isinstance(data, dict) or 'days' not in data or not isinstance(data['days'], list):
            return None

        for day in data['days']:
            if 'name' not in day or 'exercises' not in day:
                return None
            for exercise in day['exercises']:
                required = {'name', 'sets', 'reps_min', 'reps_max'}
                if not required.issubset(exercise.keys()):
                    return None

        return data
