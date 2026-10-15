from django.db.models import Sum, Count
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from .models import PlatformTransaction


@api_view(['GET'])
def revenue_summary(request):
    """Platform revenue summary. Staff only."""
    if not request.user.is_authenticated or not request.user.is_staff:
        return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

    qs = PlatformTransaction.objects.all()
    by_kind = (
        qs.values('kind')
        .annotate(total=Sum('amount'), count=Count('id'))
        .order_by('-total')
    )
    total = qs.aggregate(total=Sum('amount'))['total'] or 0

    return Response({
        'success': True,
        'currency': 'ETB',
        'total': str(total),
        'by_kind': [
            {'kind': row['kind'], 'total': str(row['total']), 'count': row['count']}
            for row in by_kind
        ],
    })


@api_view(['GET'])
def my_transactions(request):
    """The current user's own platform fees/commissions."""
    if not request.user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    rows = PlatformTransaction.objects.filter(payer=request.user).order_by('-created_at')[:20]
    return Response({
        'success': True,
        'transactions': [
            {
                'kind': r.kind,
                'amount': str(r.amount),
                'currency': r.currency,
                'status': r.status,
                'note': r.note,
                'created_at': r.created_at.isoformat(),
            }
            for r in rows
        ],
    })
