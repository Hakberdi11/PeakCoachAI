from django.urls import path

from . import views

urlpatterns = [
    path('latest/', views.LatestInsightsView.as_view(), name='insights-latest'),
]
