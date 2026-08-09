from django.urls import path

from . import views

urlpatterns = [
    path('', views.OnboardingProfileView.as_view(), name='onboarding-profile'),
]
