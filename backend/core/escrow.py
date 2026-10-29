"""Match-share escrow.

Players pay their share into escrow when they join a paid match. The money is:
  held      -> while the match is on
  released  -> to the host once the result is confirmed (host pays the venue)
  refunded  -> when the match is cancelled / auto-cancelled (per the window)
  forfeited -> when a player no-shows, or leaves too late

Gateways are called best-effort; the state machine is always recorded so a
refund/payout can also be settled manually (Telebirr etc.).
"""
from decimal import Decimal
from datetime import datetime

import requests as http_requests
from django.conf import settings
from django.db import transaction
from django.utils import timezone

from .models import MatchParticipant, MatchPot, Payment
from .monetization import money, record_transaction
from .payouts import credit_host, debit_host

CHAPA_REFUND_URL = "https://api.chapa.co/v1/refund"


# ── Policy ───────────────────────────────────────────────────────────────

def refund_percent_for(match):
    """Percent refunded when a player leaves *now*.

    Before the field is booked, players get a full refund. After booking they
    cannot leave for a refund; they must use the withdraw flow.
    """
    if match.booking_status != 'confirmed':
        return 100
    return 0


# ── State transitions ────────────────────────────────────────────────────

def hold(participant, amount=None):
    """Mark a participant's share as held in escrow (on payment success)."""
    credit = money(participant.credit_applied or 0)
    total = money(participant.match.price if amount is None else money(amount) + credit)
    participant.payment_status = 'held'
    participant.paid = True
    participant.paid_at = timezone.now()
    participant.amount_paid = total
    participant.save(update_fields=['payment_status', 'paid', 'paid_at', 'amount_paid'])
    return participant


@transaction.atomic
def release_match_funds(match):
    """Release every held share for matches without a venue pot (legacy flow)."""
    if MatchPot.objects.filter(match=match).exists():
        # The pot already paid the venue/fee and is holding any surplus.
        return money(0)
    held = list(MatchParticipant.objects.filter(match=match, payment_status='held'))
    total = money(sum((p.amount_paid or 0) for p in held))
    if held:
        MatchParticipant.objects.filter(match=match, payment_status='held').update(
            payment_status='released')
    if total > 0:
        record_transaction(
            'match_share', total, payer=match.organizer,
            reference_type='match', reference_id=match.id, status='collected',
            note=f'Escrow released to host for "{match.title}"',
        )
        credit_host(
            match.organizer, total, 'match_release', match=match,
            note=f'Escrow released for "{match.title}"',
        )
    return total


def refund_participant(participant, percent=100, reason=''):
    """Refund (fully or partially) one participant's held share."""
    if participant.payment_status != 'held':
        return money(0)
    amount = Decimal(participant.amount_paid or 0)
    refund = money(amount * Decimal(percent) / Decimal(100))

    if refund <= 0:
        participant.payment_status = 'forfeited'
    elif refund >= amount:
        participant.payment_status = 'refunded'
    else:
        participant.payment_status = 'partially_refunded'

    credit_applied = money(participant.credit_applied or 0)
    credit_refund = money(credit_applied * Decimal(percent) / Decimal(100))
    participant.credit_applied = money(credit_applied - credit_refund)
    participant.save(update_fields=['payment_status', 'credit_applied'])

    if credit_refund > 0:
        from .credits import credit_player
        credit_player(
            participant.user, credit_refund, 'adjustment', match=participant.match,
            note='Credit returned from a match',
        )
    if refund > 0:
        _refund_via_gateway(participant, refund, reason)
    return refund


def refund_match_funds(match, reason='', percent=100):
    """Refund all held shares (e.g. when a match is cancelled)."""
    total = money(0)
    for p in MatchParticipant.objects.filter(match=match, payment_status='held'):
        total += refund_participant(p, percent=percent, reason=reason)
    return total


@transaction.atomic
def forfeit_no_shows(match, user_ids):
    """No-shows lose their share; it goes to the pot (or host for legacy matches)."""
    if not user_ids:
        return money(0)
    qs = MatchParticipant.objects.filter(match=match, user_id__in=user_ids, payment_status='held')
    total = money(sum((p.amount_paid or 0) for p in qs))
    qs.update(payment_status='forfeited')
    if total <= 0:
        return total

    pot = MatchPot.objects.select_for_update().filter(match=match).first()
    if pot is None:
        credit_host(
            match.organizer, total, 'no_show_forfeit', match=match,
            note=f'No-show forfeit for "{match.title}"',
        )
        return total

    if pot.status == 'booked':
        pot.surplus = money(pot.surplus + total)
        pot.save(update_fields=['surplus'])
        return total

    if pot.status == 'settled':
        from .credits import credit_player
        from .match_pot import active_participants
        participants = list(active_participants(match))
        if participants:
            per_player = money(total / len(participants))
            allocated = money(0)
            for index, participant in enumerate(participants):
                share = per_player
                if index == len(participants) - 1:
                    share = money(total - allocated)
                if share > 0:
                    credit_player(
                        participant.user, share, 'match_surplus', match=match,
                        note=f'No-show forfeit from "{match.title}"',
                    )
                    allocated = money(allocated + share)
            return total

    # Cancelled pot or no active players: legacy host credit.
    credit_host(
        match.organizer, total, 'no_show_forfeit', match=match,
        note=f'No-show forfeit for "{match.title}"',
    )
    return total


def escrow_summary(match):
    """Totals for the match's escrow (for the API + host view)."""
    participants = MatchParticipant.objects.filter(match=match)
    totals = {}
    for status in ('held', 'released', 'refunded', 'partially_refunded', 'forfeited', 'unpaid'):
        totals[status] = money(sum(
            (p.amount_paid or 0) for p in participants if p.payment_status == status))
    totals['share'] = money(match.price)
    totals['expected'] = money(Decimal(match.price) * participants.count())
    totals['held_count'] = participants.filter(payment_status='held').count()
    totals['paid_count'] = participants.exclude(payment_status='unpaid').count()
    totals['total_count'] = participants.count()
    totals['confirmed_count'] = participants.filter(booking_confirmed=True).count()
    return totals


# ── Field-booking flow ───────────────────────────────────────────────────

def all_players_confirmed(match):
    """True when every active joined player (other than the host) has confirmed."""
    qs = MatchParticipant.objects.filter(
        match=match, withdrawn_at__isnull=True).exclude(user_id=match.organizer_id)
    total = qs.count()
    if total == 0:
        return True  # host-only match — the host's request is the confirmation
    return qs.filter(booking_confirmed=True).count() == total


def venue_cancellation_fee(booking):
    """The venue's late-cancellation fee for a booking (0 outside the window)."""
    venue = booking.venue
    window = venue.cancellation_hours or 0
    percent = venue.cancellation_fee_percent or 0
    if window <= 0 or percent <= 0:
        return money(0)

    booking_dt = timezone.make_aware(datetime.combine(booking.date, booking.start_time))
    hours = (booking_dt - timezone.now()).total_seconds() / 3600
    if hours >= window:
        return money(0)
    return money(Decimal(booking.total_price) * Decimal(percent) / Decimal(100))


@transaction.atomic
def cancel_and_settle(match, reason='', venue_fee=None):
    """Cancel a match: refund every player, charge the host for the damage.

    Held money is simply returned. Money already released to the host is
    fronted by the platform and booked against the host as a penalty.
    """
    refunded = money(0)
    fronted = money(0)

    for p in MatchParticipant.objects.filter(match=match):
        if p.payment_status == 'held':
            refunded += refund_participant(p, percent=100, reason=reason)
        elif p.payment_status == 'released':
            amount = money(p.amount_paid or 0)
            p.payment_status = 'refunded'
            p.save(update_fields=['payment_status'])
            refunded += amount
            fronted += amount

    penalty = money(fronted + money(venue_fee or 0))
    if fronted > 0:
        debit_host(
            match.organizer, fronted, 'cancellation_clawback', match=match,
            note=f'Platform fronted refunds after cancelling "{match.title}"',
        )
    if penalty > 0:
        record_transaction(
            'host_penalty', penalty, payer=match.organizer,
            reference_type='match', reference_id=match.id, status='pending',
            note=f'Host penalty for cancelling "{match.title}" ({reason})',
        )
    return {'refunded': refunded, 'fronted': fronted, 'penalty': penalty}


# ── Gateway (best effort) ────────────────────────────────────────────────

def _refund_via_gateway(participant, amount, reason=''):
    """Ask Chapa to refund; always record the state so it can be settled manually."""
    payment = Payment.objects.filter(
        user=participant.user,
        payment_type='match_share',
        reference_type='match',
        reference_id=participant.match_id,
        status='success',
    ).first()
    if not payment:
        return False

    payment.status = 'refunded'
    payment.save(update_fields=['status'])

    secret = getattr(settings, 'CHAPA_SECRET_KEY', '')
    if not secret:
        return False
    try:
        http_requests.post(
            CHAPA_REFUND_URL,
            json={'tx_ref': payment.tx_ref, 'reason': reason or 'Match cancelled'},
            headers={'Authorization': f'Bearer {secret}', 'Content-Type': 'application/json'},
            timeout=20,
        )
        return True
    except http_requests.RequestException:
        return False
