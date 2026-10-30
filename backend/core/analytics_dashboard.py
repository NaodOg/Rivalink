import json
from datetime import datetime, timedelta

from django.conf import settings
from django.contrib.admin.views.decorators import staff_member_required
from django.db.models import Count
from django.http import HttpResponse
from django.shortcuts import render
from django.utils import timezone

from .analytics import build_report
from .analytics_markdown import render_markdown
from .ml import CHURN_MIN_USERS, FILL_MIN_MATCHES, JOIN_MIN_SAMPLES, model_status
from .models import NotificationBandit, RecommendationExposure


def _login_url():
    admin = getattr(settings, 'ADMIN_URL', 'admin/')
    if not admin.endswith('/'):
        admin += '/'
    return f'/{admin}login/'


LOGIN_URL = _login_url()


def _days(request):
    try:
        days = int(request.GET.get('days', 30))
    except (TypeError, ValueError):
        days = 30
    return max(7, min(days, 365))


def _growth_snapshot(days):
    now = timezone.now()
    since = now - timedelta(days=days)
    exposures = RecommendationExposure.objects.filter(created_at__gte=since)
    variants = [
        {'variant': row['variant'] or '—', 'count': row['n']}
        for row in exposures.values('variant').annotate(n=Count('id')).order_by('-n')
    ]
    bandit_trials = sum(
        max(0, row.alpha + row.beta - 2)
        for row in NotificationBandit.objects.all()
    )
    return {
        'exposures': exposures.count(),
        'settled_exposures': exposures.filter(
            created_at__lte=now - timedelta(hours=24)).count(),
        'variants': variants,
        'models': model_status(),
        'bandit_trials': bandit_trials,
        'join_threshold': JOIN_MIN_SAMPLES,
        'churn_threshold': CHURN_MIN_USERS,
        'fill_threshold': FILL_MIN_MATCHES,
    }


@staff_member_required(login_url=LOGIN_URL)
def dashboard(request):
    days = _days(request)
    report = build_report(days)
    return render(request, 'analytics/dashboard.html', {
        'report': report,
        'growth': _growth_snapshot(days),
        'days': days,
        'generated_at': datetime.now().strftime('%d %b %Y, %H:%M'),
    })


@staff_member_required(login_url=LOGIN_URL)
def export_report(request):
    days = _days(request)
    fmt = (request.GET.get('format') or 'md').lower()
    report = build_report(days)
    stamp = datetime.now().strftime('%Y-%m-%d')

    if fmt == 'json':
        payload = json.dumps(report, indent=2, default=str)
        content_type = 'application/json'
        filename = f'victiqo-analytics-{stamp}.json'
    else:
        payload = render_markdown(report)
        content_type = 'text/markdown; charset=utf-8'
        filename = f'victiqo-analytics-{stamp}.md'

    response = HttpResponse(payload, content_type=content_type)
    response['Content-Disposition'] = f'attachment; filename="{filename}"'
    return response
