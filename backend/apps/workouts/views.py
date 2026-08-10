from datetime import timedelta

from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.adaptation.services.engine import evaluate_feedback, evaluate_reps
from apps.onboarding.serializers import OnboardingProfileSerializer
from apps.progress.services.streak import update_streak_on_finish

from .models import Exercise, PlannedExercise, WorkoutDay, WorkoutFeedback, WorkoutPlan, WorkoutSession
from .serializers import (
    ExerciseLogSerializer,
    ExerciseSerializer,
    PlannedExerciseSerializer,
    WorkoutDaySerializer,
    WorkoutFeedbackSerializer,
    WorkoutPlanSerializer,
    WorkoutSessionSerializer,
    WorkoutSessionSummarySerializer,
)
from .services import session_service
from .services import plan_edit_service
from .services.plan_generator import PlanGenerationError, WorkoutPlanGenerator

# A session left in_progress with no activity for this long is treated as
# abandoned rather than left dangling forever (WorkoutSession.Status.ABANDONED
# previously existed on the model but nothing ever set it).
_STALE_SESSION_HOURS = 12


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


class RevisePlanView(APIView):
    """Revises the user's active plan per a free-text instruction, e.g.
    'too much volume on leg day'. The instruction is also stored as a
    CoachingNote so future generations/revisions keep honoring it."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        instruction = (request.data.get('instruction') or '').strip()
        if not instruction:
            return Response({'detail': 'instruction is required.'}, status=status.HTTP_400_BAD_REQUEST)
        try:
            plan, change_summary = WorkoutPlanGenerator().revise(request.user, instruction)
        except PlanGenerationError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)
        data = WorkoutPlanSerializer(plan).data
        data['change_summary'] = change_summary
        return Response(data, status=status.HTTP_200_OK)


class ExerciseListView(APIView):
    """Catalog search backing the manual 'add exercise' picker. Defaults to the
    requesting user's own equipment when no equipment filter is given."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        queryset = Exercise.objects.all()

        muscle_group = request.query_params.get('muscle_group')
        if muscle_group:
            queryset = queryset.filter(muscle_group=muscle_group)

        equipment = request.query_params.getlist('equipment')
        if not equipment:
            from apps.onboarding.models import OnboardingProfile

            profile = OnboardingProfile.objects.filter(user=request.user).only('equipment').first()
            equipment = profile.equipment if profile else []

        if equipment:
            queryset = [
                exercise for exercise in queryset
                if not exercise.equipment_needed or set(exercise.equipment_needed) & set(equipment)
            ]

        return Response(ExerciseSerializer(queryset, many=True).data)


def _get_active_plan_day(request, day_id):
    return get_object_or_404(WorkoutDay, id=day_id, plan__user=request.user, plan__is_active=True)


def _get_active_plan_exercise(request, exercise_id):
    return get_object_or_404(
        PlannedExercise, id=exercise_id, day__plan__user=request.user, day__plan__is_active=True
    )


class PlanDayExercisesView(APIView):
    """Add an exercise to a day of the user's active plan, sourced from the
    Exercise catalog (or a freeform name, matching how plan generation already
    produces freeform names)."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, day_id):
        day = _get_active_plan_day(request, day_id)
        try:
            exercise = plan_edit_service.add_exercise(
                day,
                exercise_name=request.data['exercise_name'],
                target_sets=request.data['target_sets'],
                target_reps_min=request.data['target_reps_min'],
                target_reps_max=request.data['target_reps_max'],
                rest_seconds=request.data['rest_seconds'],
                target_rir=request.data.get('target_rir'),
            )
        except KeyError as exc:
            return Response({'detail': f'Missing field: {exc}'}, status=status.HTTP_400_BAD_REQUEST)
        return Response(PlannedExerciseSerializer(exercise).data, status=status.HTTP_201_CREATED)


class PlanDayExercisesReorderView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, day_id):
        day = _get_active_plan_day(request, day_id)
        try:
            plan_edit_service.reorder_exercises(day, request.data.get('exercise_ids', []))
        except plan_edit_service.PlanEditError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(WorkoutDaySerializer(day).data)


class PlanExerciseDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, exercise_id):
        exercise = _get_active_plan_exercise(request, exercise_id)
        fields = {
            key: value
            for key, value in request.data.items()
            if key in {'exercise_name', 'target_sets', 'target_reps_min', 'target_reps_max', 'rest_seconds', 'target_rir', 'order'}
        }
        try:
            exercise = plan_edit_service.update_exercise(exercise, **fields)
        except plan_edit_service.PlanEditError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(PlannedExerciseSerializer(exercise).data)

    def delete(self, request, exercise_id):
        exercise = _get_active_plan_exercise(request, exercise_id)
        plan_edit_service.remove_exercise(exercise)
        return Response(status=status.HTTP_204_NO_CONTENT)


def _get_session(request, session_id):
    return get_object_or_404(WorkoutSession, id=session_id, user=request.user)


class StartSessionView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        day_id = request.data.get('workout_day')
        day = get_object_or_404(WorkoutDay, id=day_id, plan__user=request.user)

        stale_cutoff = timezone.now() - timedelta(hours=_STALE_SESSION_HOURS)
        WorkoutSession.objects.filter(
            user=request.user, status=WorkoutSession.Status.IN_PROGRESS, started_at__lt=stale_cutoff
        ).update(status=WorkoutSession.Status.ABANDONED)

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
                rir=request.data.get('rir'),
                is_warmup=request.data.get('is_warmup', False),
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
