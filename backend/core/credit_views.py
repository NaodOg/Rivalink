"""Player credit balance + ledger endpoints."""
from rest_framework.decorators import api_view
from rest_framework.response import Response

from .credits import account_for, entry_dict


@api_view(['GET'])
def player_credits(request):
    if not request.user.is_authenticated:
        return Response({'success': False, 'message': 'Authentication required'},
                        status=401)
    account = account_for(request.user)
    entries = account.entries.select_related('match')[:50]
    return Response({
        'success': True,
        'balance': str(account.balance),
        'entries': [entry_dict(entry) for entry in entries],
    })
