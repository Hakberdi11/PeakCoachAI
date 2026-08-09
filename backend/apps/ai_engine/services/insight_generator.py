import json

from .openai_provider import OpenAIProvider


class InsightGenerationError(Exception):
    pass


def _build_prompt(user) -> str | None:
    from apps.adaptation.models import AdaptationHistory
    from apps.progress.models import PersonalRecord
    from apps.workouts.models import WorkoutSession

    sessions = list(
        WorkoutSession.objects.filter(user=user, status=WorkoutSession.Status.COMPLETED)
        .order_by('-started_at')[:10]
    )
    if not sessions:
        return None

    session_lines = '\n'.join(
        f'- {s.started_at.date()}: {s.workout_day.name if s.workout_day else "workout"}'
        for s in sessions
    )

    prs = PersonalRecord.objects.filter(user=user).order_by('-achieved_at')[:5]
    pr_lines = '\n'.join(f'- {pr.exercise_name}: {pr.weight}kg x {pr.reps}' for pr in prs) or 'none yet'

    adaptations = AdaptationHistory.objects.filter(user=user)[:5]
    adaptation_lines = (
        '\n'.join(f'- {a.exercise_name or "Overall"}: {a.decision} ({a.reason})' for a in adaptations)
        or 'none yet'
    )

    return f"""
You are an AI fitness coach reviewing a client's recent training history.

Recent workouts:
{session_lines}

Recent personal records:
{pr_lines}

Recent coaching adjustments:
{adaptation_lines}

Write 1 to 3 short, encouraging, specific insights about this athlete's progress and consistency.
Each insight must be at most 2 sentences. Respond with ONLY a JSON object of this exact shape:
{{"insights": [{{"text": "string", "category": "progress|consistency|adaptation"}}]}}
"""


def generate_insights(user) -> list[dict]:
    prompt = _build_prompt(user)
    if prompt is None:
        return []

    provider = OpenAIProvider()
    raw = provider.generate_completion(prompt)

    try:
        data = json.loads(raw)
        insights = data['insights']
        assert isinstance(insights, list)
        for insight in insights:
            assert 'text' in insight
    except (json.JSONDecodeError, KeyError, AssertionError, TypeError) as exc:
        raise InsightGenerationError('AI provider did not return valid insights.') from exc

    return insights
