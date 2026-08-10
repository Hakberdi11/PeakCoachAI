from django.db.models import F, FloatField, Sum
from django.db.models.functions import Coalesce
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.workouts.models import SetLog, WorkoutSession

from .models import PersonalRecord, WorkoutStreak
from .serializers import PersonalRecordSerializer
from .services.streak import rolling_completion_rate


class ProgressSummaryView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user

        streak, _ = WorkoutStreak.objects.get_or_create(user=user)

        total_workouts = WorkoutSession.objects.filter(
            user=user, status=WorkoutSession.Status.COMPLETED
        ).count()

        total_volume = SetLog.objects.filter(exercise_log__session__user=user).aggregate(
            total=Coalesce(Sum(F('weight') * F('reps'), output_field=FloatField()), 0.0)
        )['total']

        personal_records = PersonalRecord.objects.filter(user=user)[:20]

        return Response(
            {
                'current_streak': streak.current_streak,
                'longest_streak': streak.longest_streak,
                'rolling_completion_rate': rolling_completion_rate(user),
                'total_workouts': total_workouts,
                'total_volume': total_volume,
                'personal_records': PersonalRecordSerializer(personal_records, many=True).data,
            }
        )


class ProgressHistoryView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        sessions = (
            WorkoutSession.objects.filter(
                user=request.user, status=WorkoutSession.Status.COMPLETED
            )
            .annotate(
                volume=Coalesce(
                    Sum(
                        F('exercise_logs__sets__weight') * F('exercise_logs__sets__reps'),
                        output_field=FloatField(),
                    ),
                    0.0,
                )
            )
            .order_by('started_at')
        )

        return Response(
            [
                {
                    'id': session.id,
                    'day_name': session.workout_day.name if session.workout_day else None,
                    'started_at': session.started_at,
                    'volume': session.volume,
                }
                for session in sessions
            ]
        )
