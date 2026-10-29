"""Host payable ledger and manual payout workflow.

The gateway collects player shares into the platform account. When a share is
released, the host is credited here. Hosts request a payout; staff mark it paid
with a bank/Telebirr reference after transferring the money. This keeps
"released" (host is entitled) separate from "paid out" (money left the platform).
"""
from django.db import transaction
from django.db.models import F
from django.utils import timezone

from .models import HostAccount, HostLedgerEntry, HostPayout
from .monetization import HOST_PAYOUT_MIN_ETB, money


def _clean_destination(value):
    return (value or '').strip()[:200]


def account_for(user, lock=False):
    qs = HostAccount.objects.select_for_update() if lock else HostAccount.objects
    account, _ = qs.get_or_create(user=user)
    return account


@transaction.atomic
def credit_host(user, amount, kind, match=None, note='', payout=None):
    """Add money the host is entitled to. Returns the ledger entry or None."""
    amount = money(amount)
    if amount <= 0:
        return None
    account = account_for(user, lock=True)
    HostAccount.objects.filter(pk=account.pk).update(
        available_balance=F('available_balance') + amount)
    return HostLedgerEntry.objects.create(
        account=account,
        amount=amount,
        kind=kind,
        match=match,
        payout=payout,
        note=(note or '')[:300],
    )


@transaction.atomic
def debit_host(user, amount, kind, match=None, note='', allow_negative=True):
    """Claw back money (e.g. the platform fronted refunds after a cancellation)."""
    amount = money(amount)
    if amount <= 0:
        return None
    account = account_for(user, lock=True)
    if not allow_negative and account.available_balance < amount:
        raise ValueError('Insufficient host balance')
    HostAccount.objects.filter(pk=account.pk).update(
        available_balance=F('available_balance') - amount)
    return HostLedgerEntry.objects.create(
        account=account,
        amount=-amount,
        kind=kind,
        match=match,
        note=(note or '')[:300],
    )


@transaction.atomic
def request_payout(user, amount, method='bank', destination='', note=''):
    amount = money(amount)
    if amount <= 0:
        raise ValueError('Payout amount must be greater than zero')
    if amount < HOST_PAYOUT_MIN_ETB:
        raise ValueError(f'Minimum payout is Br {HOST_PAYOUT_MIN_ETB}')

    valid_methods = {choice for choice, _label in HostPayout.METHOD_CHOICES}
    if method not in valid_methods:
        raise ValueError('Unsupported payout method')

    destination = _clean_destination(destination)
    if method in ('bank', 'telebirr') and not destination:
        raise ValueError('A payout destination is required')

    account = account_for(user, lock=True)
    if amount > account.available_balance:
        raise ValueError('Payout exceeds your available balance')
    if HostPayout.objects.filter(
        account=account, status__in=('requested', 'processing')).exists():
        raise ValueError('You already have a payout in progress')

    payout = HostPayout.objects.create(
        account=account,
        user=user,
        amount=amount,
        method=method,
        destination=destination,
        note=(note or '')[:2000],
    )
    HostAccount.objects.filter(pk=account.pk).update(
        available_balance=F('available_balance') - amount,
        pending_balance=F('pending_balance') + amount,
    )
    HostLedgerEntry.objects.create(
        account=account,
        amount=-amount,
        kind='payout_request',
        payout=payout,
        note=f'Payout requested via {payout.get_method_display()}',
    )
    return payout


@transaction.atomic
def mark_payout_paid(payout, by_user, reference='', note=''):
    payout = HostPayout.objects.select_for_update().get(pk=payout.pk)
    if payout.status not in ('requested', 'processing'):
        raise ValueError('This payout has already been processed')
    reference = (reference or '').strip()
    if not reference:
        raise ValueError('A payment reference is required')

    account = HostAccount.objects.select_for_update().get(pk=payout.account_id)
    HostAccount.objects.filter(pk=account.pk).update(
        pending_balance=F('pending_balance') - payout.amount,
        paid_out_total=F('paid_out_total') + payout.amount,
    )
    payout.status = 'paid'
    payout.reference = reference[:200]
    payout.admin_note = (note or '')[:2000]
    payout.processed_at = timezone.now()
    payout.processed_by = by_user
    payout.save(update_fields=[
        'status', 'reference', 'admin_note', 'processed_at', 'processed_by'])
    return payout


@transaction.atomic
def reject_payout(payout, by_user, note=''):
    payout = HostPayout.objects.select_for_update().get(pk=payout.pk)
    if payout.status not in ('requested', 'processing'):
        raise ValueError('This payout has already been processed')

    account = HostAccount.objects.select_for_update().get(pk=payout.account_id)
    HostAccount.objects.filter(pk=account.pk).update(
        pending_balance=F('pending_balance') - payout.amount,
        available_balance=F('available_balance') + payout.amount,
    )
    HostLedgerEntry.objects.create(
        account=account,
        amount=payout.amount,
        kind='payout_rejected',
        payout=payout,
        note='Payout rejected — funds returned to available balance',
    )
    payout.status = 'rejected'
    payout.admin_note = (note or '')[:2000]
    payout.processed_at = timezone.now()
    payout.processed_by = by_user
    payout.save(update_fields=[
        'status', 'admin_note', 'processed_at', 'processed_by'])
    return payout


@transaction.atomic
def cancel_payout(payout, user):
    """Host cancels their own request before staff process it."""
    payout = HostPayout.objects.select_for_update().get(pk=payout.pk)
    if payout.user_id != user.id:
        raise ValueError('Not your payout')
    if payout.status != 'requested':
        raise ValueError('Only a requested payout can be cancelled')

    account = HostAccount.objects.select_for_update().get(pk=payout.account_id)
    HostAccount.objects.filter(pk=account.pk).update(
        pending_balance=F('pending_balance') - payout.amount,
        available_balance=F('available_balance') + payout.amount,
    )
    HostLedgerEntry.objects.create(
        account=account,
        amount=payout.amount,
        kind='payout_cancelled',
        payout=payout,
        note='Payout cancelled by host',
    )
    payout.status = 'cancelled'
    payout.processed_at = timezone.now()
    payout.save(update_fields=['status', 'processed_at'])
    return payout


def account_summary(account):
    return {
        'available': str(money(account.available_balance)),
        'pending': str(money(account.pending_balance)),
        'paid_out': str(money(account.paid_out_total)),
        'minimum_payout': str(money(HOST_PAYOUT_MIN_ETB)),
        'has_payout_in_progress': HostPayout.objects.filter(
            account=account, status__in=('requested', 'processing')).exists(),
    }


def payout_dict(payout):
    return {
        'id': payout.id,
        'amount': str(payout.amount),
        'status': payout.status,
        'method': payout.method,
        'destination': payout.destination,
        'reference': payout.reference,
        'note': payout.note,
        'admin_note': payout.admin_note,
        'requested_at': payout.requested_at.isoformat(),
        'processed_at': payout.processed_at.isoformat() if payout.processed_at else None,
    }


def entry_dict(entry):
    return {
        'id': entry.id,
        'amount': str(entry.amount),
        'kind': entry.kind,
        'match_id': entry.match_id,
        'match_title': entry.match.title if entry.match else None,
        'payout_id': entry.payout_id,
        'note': entry.note,
        'created_at': entry.created_at.isoformat(),
    }
