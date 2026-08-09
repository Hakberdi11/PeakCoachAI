from django.urls import path

from . import views

urlpatterns = [
    path('summary/', views.ProgressSummaryView.as_view(), name='progress-summary'),
    path('history/', views.ProgressHistoryView.as_view(), name='progress-history'),
]
