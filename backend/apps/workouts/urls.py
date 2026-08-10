from django.urls import path

from . import views

urlpatterns = [
    path('plans/preview/', views.GeneratePlanPreviewView.as_view(), name='generate-plan-preview'),
    path('plans/save-preview/', views.SavePreviewPlanView.as_view(), name='save-preview-plan'),
    path('plans/generate/', views.GeneratePlanView.as_view(), name='generate-plan'),
    path('plans/active/', views.ActivePlanView.as_view(), name='active-plan'),
    path('plans/revise/', views.RevisePlanView.as_view(), name='revise-plan'),
    path(
        'plans/active/days/<int:day_id>/exercises/',
        views.PlanDayExercisesView.as_view(),
        name='plan-day-exercises',
    ),
    path(
        'plans/active/days/<int:day_id>/exercises/reorder/',
        views.PlanDayExercisesReorderView.as_view(),
        name='plan-day-exercises-reorder',
    ),
    path(
        'plans/active/exercises/<int:exercise_id>/',
        views.PlanExerciseDetailView.as_view(),
        name='plan-exercise-detail',
    ),
    path('exercises/', views.ExerciseListView.as_view(), name='exercise-list'),
    path('sessions/start/', views.StartSessionView.as_view(), name='session-start'),
    path('sessions/<int:session_id>/', views.SessionDetailView.as_view(), name='session-detail'),
    path('sessions/<int:session_id>/log-set/', views.LogSetView.as_view(), name='session-log-set'),
    path(
        'sessions/<int:session_id>/skip-exercise/',
        views.SkipExerciseView.as_view(),
        name='session-skip-exercise',
    ),
    path(
        'sessions/<int:session_id>/replace-exercise/',
        views.ReplaceExerciseView.as_view(),
        name='session-replace-exercise',
    ),
    path('sessions/<int:session_id>/finish/', views.FinishSessionView.as_view(), name='session-finish'),
    path(
        'sessions/<int:session_id>/feedback/',
        views.SessionFeedbackView.as_view(),
        name='session-feedback',
    ),
    path('history/', views.SessionHistoryView.as_view(), name='session-history'),
]
