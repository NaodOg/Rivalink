"""Reward notification bandit arms based on whether users returned within 24h.

    python manage.py update_bandits
"""
from django.core.management.base import BaseCommand

from core.bandit import update_bandits


class Command(BaseCommand):
    help = 'Update notification bandits from settled 24h outcomes.'

    def add_arguments(self, parser):
        parser.add_argument('--days', type=int, default=7)

    def handle(self, *args, **options):
        updated = update_bandits(days=options['days'])
        self.stdout.write(self.style.SUCCESS(
            f'Bandits updated from {updated} settled notification(s).'))
