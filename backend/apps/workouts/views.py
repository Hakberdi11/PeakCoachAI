from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.adaptation.services.engine import evaluate_feedback, evaluate_reps
from apps.onboarding.serializers import OnboardingProfileSerializer
from apps.progress.services.streak import update_streak_on_finish

from .models import WorkoutDay, WorkoutFeedback, WorkoutPlan, WorkoutSession
from .serializers import (
    ExerciseLogSerializer,
    WorkoutFeedbackSerializer,
    WorkoutPlanSerializer,
    WorkoutSessionSerializer,
    WorkoutSessionSummarySerializer,
)
from .services import session_service
from .services.plan_generator import PlanGenerationError, WorkoutPlanGenerator


class GeneratePlanPreviewView(APIView):
    """Anonymous: generates a plan from onboarding answers without persisting anything.
    Lets a prospective user see their plan before creating an account."""

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = OnboardingProfileSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            display_plan = WorkoutPlanGenerator().generate_preview(serializer.validated_data)
        except PlanGenerationError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)
        return Response(display_plan, status=status.HTTP_200_OK)


class SavePreviewPlanView(APIView):
    """Persists a plan the user already saw in preview, without calling the AI again."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        try:
            plan = WorkoutPlanGenerator().persist(request.user, request.data)
        except PlanGenerationError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)
        return Response(WorkoutPlanSerializer(plan).data, status=status.HTTP_201_CREATED)


class GeneratePlanView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        try:
            plan = WorkoutPlanGenerator().generate(request.user)
        except PlanGenerationError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)
        return Response(WorkoutPlanSerializer(plan).data, status=status.HTTP_201_CREATED)


class ActivePlanView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        plan = WorkoutPlan.objects.filter(user=request.user, is_active=True).first()
        if plan is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(WorkoutPlanSerializer(plan).data)


def _get_session(request, session_id):
    return get_object_or_404(WorkoutSession, id=session_id, user=request.user)


class StartSessionView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        day_id = request.data.get('workout_day')
        day = get_object_or_404(WorkoutDay, id=day_id, plan__user=request.user)
        session = WorkoutSession.objects.create(user=request.user, workout_day=day)
        return Response(WorkoutSessionSerializer(session).data, status=status.HTTP_201_CREATED)


class SessionDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, session_id):
        session = _get_session(request, session_id)
        return Response(WorkoutSessionSerializer(session).data)


class LogSetView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, session_id):
        session = _get_session(request, session_id)
        try:
            exercise_log, set_log, is_new_pr = session_service.log_set(
                session,
                planned_exercise_id=request.data.get('planned_exercise'),
                exercise_name=request.data.get('exercise_name'),
                set_number=request.data['set_number'],
                weight=request.data['weight'],
                reps=request.data['reps'],
            )
        except session_service.SessionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(
            {
                'exercise_log': ExerciseLogSerializer(exercise_log).data,
                'is_new_pr': is_new_pr,
            }
        )


class SkipExerciseView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, session_id):
        session = _get_session(request, session_id)
        try:
            session_service.skip_exercise(
                session, planned_exercise_id=request.data.get('planned_exercise')
            )
        except session_service.SessionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(WorkoutSessionSerializer(session).data)


class ReplaceExerciseView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, session_id):
        session = _get_session(request, session_id)
        try:
            session_service.replace_exercise(
                session,
                planned_exercise_id=request.data.get('planned_exercise'),
                new_exercise_name=request.data.get('new_exercise_name'),
            )
        except session_service.SessionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(WorkoutSessionSerializer(session).data)


class FinishSessionView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, session_id):
        session = _get_session(request, session_id)
        session_service.finish_session(session)
        update_streak_on_finish(session.user)
        evaluate_reps(session)
        return Response(WorkoutSessionSerializer(session).data)


class SessionFeedbackView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, session_id):
        session = _get_session(request, session_id)
        serializer = WorkoutFeedbackSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        feedback, _ = WorkoutFeedback.objects.update_or_create(
            session=session, defaults=serializer.validated_data
        )
        evaluate_feedback(session, feedback)
        return Response(WorkoutSessionSerializer(session).data)


class SessionHistoryView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        sessions = WorkoutSession.objects.filter(user=request.user)
        return Response(WorkoutSessionSummarySerializer(sessions, many=True).data)
