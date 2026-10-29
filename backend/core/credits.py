"""In-app player credit from match surplus."""
from django.db import transaction
from django.db.models import F

from .models import PlayerCreditAccount, PlayerCreditEntry
from .monetization import money


def account_for(user, lock=False):
    qs = PlayerCreditAccount.objects.select_for_update() if lock else PlayerCreditAccount.objects
    account, _ = qs.get_or_create(user=user)
    return account


@transaction.atomic
def credit_player(user, amount, kind, match=None, note=''):
    amount = money(amount)
    if amount <= 0:
        return None
    account = account_for(user, lock=True)
    PlayerCreditAccount.objects.filter(pk=account.pk).update(
        balance=F('balance') + amount)
    return PlayerCreditEntry.objects.create(
        account=account,
        amount=amount,
        kind=kind,
        match=match,
        note=(note or '')[:300],
    )


@transaction.atomic
def debit_player(user, amount, kind='used', match=None, note='', allow_negative=False):
    amount = money(amount)
    if amount <= 0:
        return None
    account = account_for(user, lock=True)
    if not allow_negative and account.balance < amount:
        raise ValueError('Not enough credit')
    PlayerCreditAccount.objects.filter(pk=account.pk).update(
        balance=F('balance') - amount)
    return PlayerCreditEntry.objects.create(
        account=account,
        amount=-amount,
        kind=kind,
        match=match,
        note=(note or '')[:300],
    )


def account_summary(account):
    return {'balance': str(money(account.balance))}


def entry_dict(entry):
    return {
        'id': entry.id,
        'amount': str(entry.amount),
        'kind': entry.kind,
        'match_id': entry.match_id,
        'match_title': entry.match.title if entry.match else None,
        'note': entry.note,
        'created_at': entry.created_at.isoformat(),
    }
