"""Run retention nudges. Designed for cron / a scheduler, e.g. hourly.

    python manage.py run_engagement_jobs

Send-time windows and frequency caps are enforced here. Transactional fixture
reminders bypass the caps; everything else is rate-limited per user.
"""
from django.core.management.base import BaseCommand

from core.engagement import (
    fill_assistant, post_match_rematch, premium_expiry_nudges,
    send_fixture_reminders, streak_nudges, weekly_recap, win_back,
)


class Command(BaseCommand):
    help = 'Send retention nudges (fixtures, fill, win-back, streaks, premium, rematch, recap).'

    def handle(self, *args, **options):
        fixtures = send_fixture_reminders()
        fills = fill_assistant(respect_windows=True)
        revived = win_back(respect_windows=True)
        premium = premium_expiry_nudges(respect_windows=True)
        streaks = streak_nudges(respect_windows=True)
        rematches = post_match_rematch(respect_windows=True)
        recaps = weekly_recap(respect_windows=True)

        self.stdout.write(self.style.SUCCESS(
            f'Engagement jobs: fixtures={fixtures}, fill={fills}, '
            f'win_back={revived}, premium={premium}, streaks={streaks}, '
            f'rematch={rematches}, recap={recaps}.'
        ))
