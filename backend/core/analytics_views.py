import json
import re

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .analytics import build_report
from .models import AnalyticsEvent

EVENT_NAME_RE = re.compile(r'^[a-z0-9_]{1,80}$')
MAX_BATCH = 50
MAX_PROPERTIES_BYTES = 4096


@api_view(['POST'])
@permission_classes([AllowAny])
def ingest_analytics(request):
    """Batch ingest of client analytics events (anonymous or authenticated)."""
    payload = request.data if isinstance(request.data, dict) else {}
    events = payload.get('events')
    if not isinstance(events, list) or not events:
        return Response({'error': 'events must be a non-empty list'},
                        status=status.HTTP_400_BAD_REQUEST)
    if len(events) > MAX_BATCH:
        return Response({'error': f'Max {MAX_BATCH} events per batch'},
                        status=status.HTTP_400_BAD_REQUEST)

    session_id = str(payload.get('session_id') or '')[:64]
    anon_id = str(payload.get('anon_id') or '')[:64]
    platform = str(payload.get('platform') or 'android')[:20]
    app_version = str(payload.get('app_version') or '')[:20]
    user = request.user if request.user.is_authenticated else None

    rows = []
    for item in events:
        if not isinstance(item, dict):
            continue
        name = str(item.get('name') or '')
        if not EVENT_NAME_RE.match(name):
            continue
        props = item.get('properties') or {}
        if not isinstance(props, dict):
            props = {}
        if len(json.dumps(props)) > MAX_PROPERTIES_BYTES:
            continue
        rows.append(AnalyticsEvent(
            user=user,
            anon_id=anon_id,
            session_id=session_id,
            name=name,
            properties=props,
            platform=platform,
            app_version=app_version,
        ))

    if not rows:
        return Response({'error': 'No valid events'}, status=status.HTTP_400_BAD_REQUEST)

    for row in rows:
        row.save()
    return Response({'success': True, 'accepted': len(rows)},
                    status=status.HTTP_201_CREATED)


@api_view(['GET'])
def analytics_report(request):
    """Staff-only actionable analytics report."""
    if not request.user.is_authenticated or not request.user.is_staff:
        return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

    try:
        days = int(request.query_params.get('days', 30))
    except (TypeError, ValueError):
        days = 30
    days = max(7, min(days, 365))

    return Response({'success': True, **build_report(days)})
