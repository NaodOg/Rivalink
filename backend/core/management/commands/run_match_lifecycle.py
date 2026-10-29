"""Match lifecycle jobs:
  1. auto-cancel under-filled matches close to kickoff (and refund everyone)
  2. auto-confirm undisputed results after the review window

Run it from cron / a scheduler, e.g. every 15 minutes:
    python manage.py run_match_lifecycle
"""
from datetime import timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.utils import timezone

from core.escrow import (
    cancel_and_settle, forfeit_no_shows, release_match_funds,
)
from core.match_pot import funding_summary, settle_match_pot
from core.models import Match, MatchParticipant, MatchPot, MatchResult, VenueBooking
from core.monetization import MATCH_AUTO_CANCEL_HOURS, RESULT_AUTO_CONFIRM_HOURS
from core.push import notify


class Command(BaseCommand):
    help = 'Settle match pots, auto-cancel under-filled matches and auto-confirm results.'

    def handle(self, *args, **options):
        now = timezone.now()
        settled = 0
        released_reservations = 0
        cancelled = 0
        confirmed = 0

        # 0. Release stale unpaid reservations so the venue calendar opens up.
        stale_before = now - timedelta(hours=1)
        for booking in VenueBooking.objects.filter(
                status='reserved', match__isnull=False,
                created_at__lt=stale_before).select_related('match'):
            host_participant = MatchParticipant.objects.filter(
                match=booking.match, user=booking.match.organizer).first()
            if host_participant and host_participant.payment_status in (
                    'held', 'released', 'covered'):
                continue
            booking.status = 'cancelled'
            booking.save(update_fields=['status'])
            released_reservations += 1

        # 1. Kickoff passed -> split any remaining pot surplus as player credit.
        for pot in MatchPot.objects.filter(
                status='booked', match__date_time__lte=now).select_related('match'):
            result = settle_match_pot(pot.match)
            if result:
                settled += 1

        # 2. Under-filled matches at the 36h deadline -> cancel + refund everyone.
        horizon = now + timedelta(hours=MATCH_AUTO_CANCEL_HOURS)
        upcoming = Match.objects.filter(
            is_active=True, min_players__gt=0,
            date_time__gt=now, date_time__lte=horizon,
        ).exclude(booking_status='confirmed')
        for match in upcoming:
            funding = funding_summary(match)
            target = Decimal(funding['target'])
            collected = Decimal(funding['collected'])
            enough_players = match.current_players >= match.min_players
            enough_money = collected >= target
            if enough_players and enough_money:
                continue

            reasons = []
            if not enough_players:
                reasons.append('not enough players')
            if not enough_money:
                reasons.append(f'only Br {collected} of Br {target} collected')
            reason = ' and '.join(reasons) or 'not ready'

            booking = VenueBooking.objects.filter(match=match).first()
            if booking and booking.status != 'cancelled':
                booking.status = 'cancelled'
                booking.save(update_fields=['status'])

            settlement = cancel_and_settle(match, reason=reason)
            refunded = settlement['refunded']
            match.is_active = False
            match.booking_status = 'cancelled'
            match.cancelled_reason = f'Deadline passed — {reason}'
            match.cancelled_at = now
            match.save(update_fields=['is_active', 'booking_status', 'cancelled_reason', 'cancelled_at'])

            for p in MatchParticipant.objects.filter(match=match).select_related('user'):
                notify(
                    p.user, 'match_cancelled', 'Match cancelled',
                    f'"{match.title}" was cancelled — {reason}. '
                    f'Refunded: Br {refunded}.',
                    match=match,
                )
            cancelled += 1

        # 3. Undisputed results past the review window -> confirm + settle.
        from core.view_shared import _apply_result_rankings
        stale_before = now - timedelta(hours=RESULT_AUTO_CONFIRM_HOURS)
        for result in MatchResult.objects.filter(status='pending', created_at__lte=stale_before):
            if result.confirmations.filter(status='disputed').exists():
                continue
            result.status = 'confirmed'
            result.confirmed_at = now
            result.save(update_fields=['status', 'confirmed_at'])
            forfeit_no_shows(result.match, result.no_show_list)
            release_match_funds(result.match)
            _apply_result_rankings(result.match, result)
            confirmed += 1

        self.stdout.write(self.style.SUCCESS(
            f'Lifecycle: settled {settled} pot(s), released '
            f'{released_reservations} stale reservation(s), cancelled {cancelled} '
            f'match(es), confirmed {confirmed} result(s).'
        ))
