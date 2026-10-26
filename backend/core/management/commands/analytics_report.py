"""Generate the actionable analytics report as markdown.

Examples:
    python manage.py analytics_report
    python manage.py analytics_report --days 14 --out reports/analytics.md
"""
import os

from django.core.management.base import BaseCommand

from core.analytics import build_report


def _table(headers, rows):
    lines = ['| ' + ' | '.join(headers) + ' |',
             '|' + '|'.join([' --- '] * len(headers)) + '|']
    for row in rows:
        lines.append('| ' + ' | '.join(str(c) for c in row) + ' |')
    return '\n'.join(lines)


from core.analytics_markdown import render_markdown


class Command(BaseCommand):
    help = 'Generate the product analytics report (markdown).'

    def add_arguments(self, parser):
        parser.add_argument('--days', type=int, default=30,
                            help='Report window in days (default 30).')
        parser.add_argument('--out', type=str, default='',
                            help='Write the markdown to this file as well.')

    def handle(self, *args, **options):
        days = max(7, min(options['days'], 365))
        report = build_report(days)
        markdown = render_markdown(report)
        self.stdout.write(markdown)

        out = options.get('out')
        if out:
            os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
            with open(out, 'w', encoding='utf-8') as fh:
                fh.write(markdown)
            self.stdout.write(self.style.SUCCESS(f'\nReport written to {out}'))
