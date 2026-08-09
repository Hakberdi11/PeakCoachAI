from django.db import connection
from django.db.utils import OperationalError
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework import status


@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
    except OperationalError:
        return Response(
            {'status': 'error', 'database': 'unreachable'},
            status=status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    return Response(
        {
            'status': 'ok',
            'service': 'peak-coach-ai-backend',
            'database': 'connected',
        },
        status=status.HTTP_200_OK,
    )
