"""Train the optional ranking/retention models from stored product data.

    python manage.py train_models

Every model has a data threshold. Below it the command reports "waiting" and
the app keeps using rules. Above it, weights are stored in ModelArtifact and the
API starts blending the learned score automatically.
"""
from django.core.management.base import BaseCommand

from core.ml import (
    CHURN_MIN_USERS, FILL_MIN_MATCHES, JOIN_MIN_POSITIVES, JOIN_MIN_SAMPLES,
    train_churn_model, train_fill_model, train_join_model,
)


class Command(BaseCommand):
    help = 'Train join-propensity, churn and fill-probability models when ready.'

    def add_arguments(self, parser):
        parser.add_argument('--min-join-samples', type=int, default=JOIN_MIN_SAMPLES)
        parser.add_argument('--min-join-positives', type=int, default=JOIN_MIN_POSITIVES)
        parser.add_argument('--min-churn-users', type=int, default=CHURN_MIN_USERS)
        parser.add_argument('--min-fill-matches', type=int, default=FILL_MIN_MATCHES)

    def handle(self, *args, **options):
        results = [
            train_join_model(
                min_samples=options['min_join_samples'],
                min_positives=options['min_join_positives'],
            ),
            train_churn_model(min_users=options['min_churn_users']),
            train_fill_model(min_matches=options['min_fill_matches']),
        ]

        for result in results:
            name = result['model']
            samples = result['samples']
            positives = result['positives']
            if result['trained']:
                self.stdout.write(self.style.SUCCESS(
                    f'{name}: trained on {samples} samples ({positives} positives), '
                    f'accuracy={result.get("accuracy")}.'))
            elif result['ready']:
                self.stdout.write(self.style.WARNING(
                    f'{name}: ready but training produced no usable model '
                    f'({samples} samples, {positives} positives).'))
            else:
                threshold = result.get('min_samples') or result.get('min_users') \
                    or result.get('min_matches')
                self.stdout.write(
                    f'{name}: waiting ({samples} samples, {positives} positives; '
                    f'threshold {threshold}).')

        self.stdout.write(self.style.SUCCESS('Model check complete.'))
