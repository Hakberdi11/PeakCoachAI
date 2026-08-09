from datetime import timedelta

from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import AIInsight
from .serializers import AIInsightSerializer
from .services.insight_generator import InsightGenerationError, generate_insights


class LatestInsightsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        cutoff = timezone.now() - timedelta(hours=24)
        cached = AIInsight.objects.filter(user=request.user, created_at__gte=cutoff)
        if cached.exists():
            return Response(AIInsightSerializer(cached, many=True).data)

        try:
            insights = generate_insights(request.user)
        except InsightGenerationError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)

        created = [
            AIInsight.objects.create(
                user=request.user,
                text=insight['text'],
                category=insight.get('category', 'general'),
            )
            for insight in insights
        ]
        return Response(AIInsightSerializer(created, many=True).data)
