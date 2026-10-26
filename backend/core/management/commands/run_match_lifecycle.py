"""Match lifecycle jobs:
  1. auto-cancel under-filled matches close to kickoff (and refund everyone)
  2. auto-confirm undisputed results after the review window

Run it from cron / a scheduler, e.g. every 15 minutes:
    python manage.py run_match_lifecycle
"""
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from core.escrow import (
    cancel_and_settle, forfeit_no_shows, release_match_funds,
)
from core.models import Match, MatchParticipant, MatchResult, VenueBooking
from core.monetization import MATCH_AUTO_CANCEL_HOURS, RESULT_AUTO_CONFIRM_HOURS
from core.push import notify


class Command(BaseCommand):
    help = 'Auto-cancel under-filled matches and auto-confirm undisputed results.'

    def handle(self, *args, **options):
        now = timezone.now()
        cancelled = 0
        confirmed = 0

        # 1. Under-filled matches near kickoff -> cancel + refund everyone.
        horizon = now + timedelta(hours=MATCH_AUTO_CANCEL_HOURS)
        upcoming = Match.objects.filter(
            is_active=True, min_players__gt=0,
            date_time__gt=now, date_time__lte=horizon,
        )
        for match in upcoming:
            if match.current_players >= match.min_players:
                continue

            booking = VenueBooking.objects.filter(match=match).first()
            if booking and booking.status != 'cancelled':
                booking.status = 'cancelled'
                booking.save(update_fields=['status'])

            settlement = cancel_and_settle(match, reason='Not enough players')
            refunded = settlement['refunded']
            match.is_active = False
            match.booking_status = 'cancelled'
            match.cancelled_reason = 'Not enough players'
            match.cancelled_at = now
            match.save(update_fields=['is_active', 'booking_status', 'cancelled_reason', 'cancelled_at'])

            for p in MatchParticipant.objects.filter(match=match).select_related('user'):
                notify(
                    p.user, 'match_cancelled', 'Match cancelled',
                    f'"{match.title}" was cancelled — not enough players. '
                    f'Refunded: Br {refunded}.',
                    match=match,
                )
            cancelled += 1

        # 2. Undisputed results past the review window -> confirm + settle.
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
            f'Lifecycle: cancelled {cancelled} match(es), confirmed {confirmed} result(s).'
        ))
