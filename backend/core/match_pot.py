"""Match pot, post-booking withdrawals, funded replacements and surplus credit."""
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from .credits import credit_player
from .models import Match, MatchParticipant, MatchPot, MatchWithdrawal
from .monetization import FIELD_SERVICE_FEE_ETB, money
from .push import notify


def active_participants(match):
    return MatchParticipant.objects.filter(match=match, withdrawn_at__isnull=True)


def open_withdrawals(match):
    return MatchWithdrawal.objects.filter(match=match, status='open', share_amount__gt=0)


def service_fee_for(match):
    if not match.venue_id:
        return money(0)
    return money(FIELD_SERVICE_FEE_ETB) if match.venue.slot_price > 0 else money(0)


def funding_summary(match):
    pot = MatchPot.objects.filter(match=match).first()
    if pot:
        collected = pot.collected
        target = money(pot.venue_amount + pot.platform_fee)
        surplus = pot.surplus
    else:
        collected = money(sum(
            (p.amount_paid or 0) for p in MatchParticipant.objects.filter(
                match=match, payment_status__in=('held', 'released'))
        ))
        venue_amount = money(match.venue.slot_price) if match.venue else money(0)
        fee = service_fee_for(match)
        target = money(venue_amount + fee)
        surplus = money(max(Decimal('0'), collected - target))
    return {
        'collected': str(money(collected)),
        'target': str(money(target)),
        'service_fee': str(service_fee_for(match)),
        'venue_amount': str(money(match.venue.slot_price)) if match.venue else '0.00',
        'surplus': str(money(surplus)),
        'open_funded_spots': open_withdrawals(match).count(),
        'pot_status': pot.status if pot else '',
    }


def can_withdraw(match, user):
    if match.booking_status != 'confirmed' or not match.is_active:
        return False
    if match.date_time <= timezone.now():
        return False
    return MatchParticipant.objects.filter(
        match=match, user=user, withdrawn_at__isnull=True).exists()


@transaction.atomic
def withdraw_participant(match, user):
    match = Match.objects.select_for_update().get(pk=match.pk)
    if match.booking_status != 'confirmed':
        raise ValueError('You can only withdraw after the field is booked')
    if not match.is_active:
        raise ValueError('This match is cancelled')
    if match.date_time <= timezone.now():
        raise ValueError('The match has already started')

    participant = MatchParticipant.objects.select_for_update().filter(
        match=match, user=user).first()
    if participant is None:
        raise ValueError('You are not in this match')
    if participant.withdrawn_at is not None:
        raise ValueError('You already withdrew from this match')

    new_organizer = None
    if match.organizer_id == user.id:
        replacement = active_participants(match).exclude(user=user).order_by(
            'joined_at').first()
        if replacement is None:
            raise ValueError('You are the last active player. Cancel the match instead.')
        match.organizer = replacement.user
        match.save(update_fields=['organizer'])
        new_organizer = replacement.user

    share = money(participant.amount_paid or 0)
    participant.withdrawn_at = timezone.now()
    if participant.payment_status in ('held', 'released', 'covered', 'unpaid'):
        participant.payment_status = 'forfeited'
    participant.save(update_fields=['withdrawn_at', 'payment_status'])

    match.current_players = max(0, match.current_players - 1)
    match.save(update_fields=['current_players'])

    withdrawal = MatchWithdrawal.objects.create(
        match=match,
        user=user,
        share_amount=share,
        status='open' if share > 0 else 'closed',
        resolved_at=None if share > 0 else timezone.now(),
    )

    for p in active_participants(match).select_related('user'):
        notify(
            p.user, 'general', 'Player withdrew',
            f'{user.first_name or user.username} withdrew from "{match.title}". '
            'The spot is funded — a replacement can join free.',
            match=match,
        )
    if new_organizer is not None:
        notify(
            new_organizer, 'general', 'You are now the organizer',
            f'{user.first_name or user.username} withdrew from "{match.title}". '
            'You are now responsible for the match.',
            match=match,
        )
    return {
        'withdrawal_id': withdrawal.id,
        'share_amount': str(share),
        'new_organizer_id': new_organizer.id if new_organizer else None,
        'new_organizer_name': (new_organizer.first_name or new_organizer.username)
        if new_organizer else None,
        'funded_spots': open_withdrawals(match).count(),
        'current_players': match.current_players,
    }


@transaction.atomic
def claim_funded_spot(match, user):
    match = Match.objects.select_for_update().get(pk=match.pk)
    if match.booking_status != 'confirmed' or not match.is_active:
        raise ValueError('This match is not open for funded replacements')
    if match.date_time <= timezone.now():
        raise ValueError('The match has already started')
    if MatchParticipant.objects.filter(match=match, user=user).exists():
        raise ValueError('You already have a spot in this match')

    withdrawal = MatchWithdrawal.objects.select_for_update().filter(
        match=match, status='open', share_amount__gt=0).order_by('created_at').first()
    if withdrawal is None:
        raise ValueError('There are no funded spots available')

    participant = MatchParticipant.objects.create(
        match=match,
        user=user,
        payment_status='covered',
        paid=True,
        amount_paid=0,
        booking_confirmed=True,
        booking_confirmed_at=timezone.now(),
    )
    match.current_players += 1
    match.save(update_fields=['current_players'])

    withdrawal.status = 'replaced'
    withdrawal.replacement_user = user
    withdrawal.resolved_at = timezone.now()
    withdrawal.save(update_fields=['status', 'replacement_user', 'resolved_at'])

    notify(
        match.organizer, 'general', 'Replacement joined',
        f'{user.first_name or user.username} took a funded spot in "{match.title}".',
        match=match,
    )
    notify(
        user, 'general', 'You are in',
        f'Your spot for "{match.title}" is funded. No payment needed.',
        match=match,
    )
    return {
        'participant_id': participant.id,
        'withdrawal_id': withdrawal.id,
        'funded_spots': open_withdrawals(match).count(),
        'current_players': match.current_players,
    }


@transaction.atomic
def settle_match_pot(match, force=False):
    match = Match.objects.select_for_update().get(pk=match.pk)
    pot = MatchPot.objects.select_for_update().filter(match=match).first()
    if pot is None or pot.status != 'booked':
        return None
    if not force and match.date_time > timezone.now():
        return None

    participants = list(active_participants(match).select_related('user'))
    surplus = money(pot.surplus)
    credited = money(0)
    per_player = money(0)
    if surplus > 0 and participants:
        per_player = money(surplus / len(participants))
        allocated = money(0)
        for index, participant in enumerate(participants):
            share = per_player
            if index == len(participants) - 1:
                share = money(surplus - allocated)
            if share > 0:
                credit_player(
                    participant.user, share, 'match_surplus', match=match,
                    note=f'Surplus from "{match.title}"',
                )
                allocated = money(allocated + share)
            if share > 0:
                notify(
                    participant.user, 'general', 'Match credit added',
                    f'Br {share} credit was added to your account from "{match.title}".',
                    match=match,
                )
        credited = allocated

    MatchWithdrawal.objects.filter(match=match, status='open').update(
        status='closed', resolved_at=timezone.now())
    pot.status = 'settled'
    pot.settled_at = timezone.now()
    pot.save(update_fields=['status', 'settled_at'])

    return {
        'credited': str(credited),
        'per_player': str(per_player),
        'players': len(participants),
        'withdrawals_closed': MatchWithdrawal.objects.filter(
            match=match, status='closed').count(),
    }
