from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import OnboardingProfile
from .serializers import OnboardingProfileSerializer


class OnboardingProfileView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        try:
            profile = OnboardingProfile.objects.get(user=request.user)
        except OnboardingProfile.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(OnboardingProfileSerializer(profile).data)

    def post(self, request):
        serializer = OnboardingProfileSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        OnboardingProfile.objects.update_or_create(
            user=request.user,
            defaults={**serializer.validated_data, 'completed_at': timezone.now()},
        )
        profile = OnboardingProfile.objects.get(user=request.user)
        return Response(OnboardingProfileSerializer(profile).data, status=status.HTTP_200_OK)
