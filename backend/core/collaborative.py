"""Collaborative filtering from co-participation.

If players who joined the matches you joined also joined match X, X is probably
a good recommendation. This is item-item CF with a co-occurrence count — small
data, no model server required.
"""
from datetime import timedelta

from django.db.models import Count, F
from django.utils import timezone

from .models import MatchParticipant

MIN_HISTORY = 3
MAX_RESULTS = 100


def co_participation_scores(user, now=None):
    """Return {match_id: score 0..1} for upcoming matches, empty when cold."""
    now = now or timezone.now()
    my_match_ids = list(
        MatchParticipant.objects.filter(user=user).values_list('match_id', flat=True)
    )
    if len(my_match_ids) < MIN_HISTORY:
        return {}

    co_users = set(
        MatchParticipant.objects.filter(match_id__in=my_match_ids)
        .exclude(user=user)
        .values_list('user_id', flat=True)
    )
    if not co_users:
        return {}

    rows = (
        MatchParticipant.objects.filter(user_id__in=co_users)
        .exclude(match_id__in=my_match_ids)
        .exclude(match__organizer=user)
        .filter(
            match__is_active=True,
            match__date_time__gte=now,
            match__date_time__lte=now + timedelta(days=30),
            match__current_players__lt=F('match__max_players'),
        )
        .values('match_id')
        .annotate(n=Count('user_id', distinct=True))
        .order_by('-n')[:MAX_RESULTS]
    )
    if not rows:
        return {}

    top = max(row['n'] for row in rows)
    if top <= 0:
        return {}
    return {row['match_id']: min(1.0, row['n'] / top) for row in rows}
