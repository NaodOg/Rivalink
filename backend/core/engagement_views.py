from rest_framework.decorators import api_view
from rest_framework.response import Response

from .engagement import engagement_status


@api_view(['GET'])
def engagement(request):
    """Personal retention snapshot: streak, risk score, next best action."""
    if not request.user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=401)
    return Response({'success': True, **engagement_status(request.user)})
