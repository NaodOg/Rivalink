"""Player reliability: a simple, explainable trust score.

Used for ranking organizers, deciding who to invite to fill a match, and giving
users a reason to show up. Deliberately transparent: every input is visible.
"""
from django.db.models import Avg

from .models import PlayerRating, UserProfile

MIN_SCORE = 0
MAX_SCORE = 100


def reliability_from_counts(no_shows=0, host_cancellations=0, average_rating=None):
    score = 100 - 15 * max(0, int(no_shows or 0)) - 10 * max(0, int(host_cancellations or 0))
    if average_rating is not None:
        score += (float(average_rating) - 3.0) * 10.0
    score = int(round(max(MIN_SCORE, min(MAX_SCORE, score))))
    if score >= 90:
        label = 'excellent'
    elif score >= 75:
        label = 'good'
    elif score >= 60:
        label = 'fair'
    else:
        label = 'low'
    return {
        'score': score,
        'label': label,
        'no_shows': int(no_shows or 0),
        'host_cancellations': int(host_cancellations or 0),
        'average_rating': round(float(average_rating), 2) if average_rating is not None else None,
    }


def reliability(user, average_rating=None):
    profile = UserProfile.objects.filter(user=user).first()
    if average_rating is None:
        average_rating = PlayerRating.objects.filter(rated_user=user).aggregate(
            avg=Avg('rating'))['avg']
    return reliability_from_counts(
        profile.no_show_count if profile else 0,
        profile.host_cancel_count if profile else 0,
        average_rating,
    )


def organizer_reliability_map(matches):
    """Bulk reliability for organizers in a list of matches (2 queries total)."""
    organizers = {m.organizer for m in matches}
    profiles = {
        p.user_id: p for p in UserProfile.objects.filter(user__in=organizers)
    }
    ratings = {
        row['rated_user_id']: row['avg']
        for row in PlayerRating.objects.filter(rated_user__in=organizers)
        .values('rated_user_id').annotate(avg=Avg('rating'))
    }
    return {
        user.id: reliability_from_counts(
            profiles[user.id].no_show_count if user.id in profiles else 0,
            profiles[user.id].host_cancel_count if user.id in profiles else 0,
            ratings.get(user.id),
        )
        for user in organizers
    }
