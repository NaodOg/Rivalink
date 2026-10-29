"""Host earnings + payout endpoints."""
from decimal import Decimal, InvalidOperation

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response

from .payouts import (
    account_for, account_summary, cancel_payout, entry_dict, mark_payout_paid,
    payout_dict, reject_payout, request_payout,
)
from .models import HostPayout


def _auth_error():
    return Response({'success': False, 'message': 'Authentication required'},
                    status=status.HTTP_401_UNAUTHORIZED)


@api_view(['GET'])
def host_earnings(request):
    """Balances, ledger and payout history for the current host."""
    if not request.user.is_authenticated:
        return _auth_error()
    account = account_for(request.user)
    entries = account.entries.select_related('match', 'payout')[:50]
    payouts = account.payouts.all()[:20]
    return Response({
        'success': True,
        'account': account_summary(account),
        'ledger': [entry_dict(entry) for entry in entries],
        'payouts': [payout_dict(payout) for payout in payouts],
    })


@api_view(['GET', 'POST'])
def host_payouts(request):
    """GET payout history; POST a new payout request."""
    if not request.user.is_authenticated:
        return _auth_error()

    if request.method == 'GET':
        account = account_for(request.user)
        payouts = account.payouts.all()[:50]
        return Response({
            'success': True,
            'payouts': [payout_dict(payout) for payout in payouts],
            'account': account_summary(account),
        })

    try:
        amount = Decimal(str(request.data.get('amount', '0')))
    except (InvalidOperation, TypeError, ValueError):
        return Response({'success': False, 'message': 'Invalid payout amount'},
                        status=status.HTTP_400_BAD_REQUEST)

    try:
        payout = request_payout(
            request.user,
            amount,
            method=(request.data.get('method') or 'bank').strip(),
            destination=request.data.get('destination', ''),
            note=request.data.get('note', ''),
        )
    except ValueError as exc:
        return Response({'success': False, 'message': str(exc)},
                        status=status.HTTP_400_BAD_REQUEST)

    account = account_for(request.user)
    return Response({
        'success': True,
        'payout': payout_dict(payout),
        'account': account_summary(account),
    }, status=status.HTTP_201_CREATED)


@api_view(['POST'])
def cancel_host_payout(request, payout_id):
    if not request.user.is_authenticated:
        return _auth_error()
    payout = HostPayout.objects.filter(
        id=payout_id, user=request.user).first()
    if payout is None:
        return Response({'success': False, 'message': 'Payout not found'},
                        status=status.HTTP_404_NOT_FOUND)
    try:
        cancel_payout(payout, request.user)
    except ValueError as exc:
        return Response({'success': False, 'message': str(exc)},
                        status=status.HTTP_400_BAD_REQUEST)
    return Response({
        'success': True,
        'payout': payout_dict(payout),
        'account': account_summary(account_for(request.user)),
    })


@api_view(['POST'])
@permission_classes([IsAdminUser])
def review_host_payout(request, payout_id):
    """Staff marks a payout paid (with reference) or rejected."""
    payout = HostPayout.objects.filter(id=payout_id).first()
    if payout is None:
        return Response({'success': False, 'message': 'Payout not found'},
                        status=status.HTTP_404_NOT_FOUND)

    action = (request.data.get('action') or '').strip()
    try:
        if action == 'paid':
            mark_payout_paid(
                payout, request.user,
                reference=request.data.get('reference', ''),
                note=request.data.get('note', ''),
            )
        elif action == 'rejected':
            reject_payout(payout, request.user, note=request.data.get('note', ''))
        else:
            return Response({'success': False,
                             'message': 'action must be "paid" or "rejected"'},
                            status=status.HTTP_400_BAD_REQUEST)
    except ValueError as exc:
        return Response({'success': False, 'message': str(exc)},
                        status=status.HTTP_400_BAD_REQUEST)

    return Response({
        'success': True,
        'payout': payout_dict(payout),
        'account': account_summary(account_for(payout.user)),
    })
