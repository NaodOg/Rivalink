from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import timedelta

from core.models import Match, MatchParticipant
from core.push import notify


class Command(BaseCommand):
    help = 'Push a reminder to participants of matches starting within the next hour.'

    def handle(self, *args, **options):
        now = timezone.now()
        soon = now + timedelta(hours=1)
        matches = Match.objects.filter(
            is_active=True,
            reminder_sent=False,
            date_time__gte=now,
            date_time__lte=soon,
        )
        count = 0
        for match in matches:
            for p in MatchParticipant.objects.filter(match=match).select_related('user'):
                notify(
                    p.user,
                    'general',
                    'Match starting soon',
                    f'"{match.title}" kicks off at {match.date_time.strftime("%H:%M")}.',
                    match=match,
                )
            match.reminder_sent = True
            match.save(update_fields=['reminder_sent'])
            count += 1
        self.stdout.write(self.style.SUCCESS(f'Reminders sent for {count} match(es).'))
