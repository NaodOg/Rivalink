"""Lightweight, dependency-free learning layer.

Pure-Python logistic regression trained from data we already store. Every model
is optional: callers fall back to rules when an artifact has not reached its
data threshold yet. Weights live in the database (``ModelArtifact``), so a
weekly ``train_models`` run is the whole deployment.
"""
import math
from collections import defaultdict
from datetime import timedelta

from django.contrib.auth.models import User
from django.db.models import Avg, Count
from django.utils import timezone

from .collaborative import co_participation_scores
from .models import (
    AnalyticsEvent, Match, MatchParticipant, ModelArtifact, PlayerRating,
    RecommendationExposure, UserProfile, VenueBooking,
)

JOIN_MIN_SAMPLES = 200
JOIN_MIN_POSITIVES = 30
CHURN_MIN_USERS = 300
FILL_MIN_MATCHES = 50

JOIN_FEATURES = [
    'sport_fit', 'city_fit', 'hours_fit', 'scarcity_fit', 'skill_fit',
    'price_fit', 'organizer_premium', 'organizer_reliability',
    'cf_score', 'prior_exposures', 'sport_join_rate', 'weekend',
    'hour_sin', 'hour_cos',
]

CHURN_FEATURES = [
    'days_since_active', 'sessions_7d', 'sessions_28d', 'matches_joined_28d',
    'matches_hosted_28d', 'streak_weeks', 'no_shows', 'is_premium',
    'reliability', 'upcoming_matches',
]

FILL_FEATURES = [
    'lead_days', 'capacity', 'price_scaled', 'min_players', 'weekend',
    'hour_sin', 'hour_cos', 'organizer_reliability', 'is_soccer',
    'is_basketball', 'is_tennis', 'is_volleyball', 'is_cricket',
    'is_esports', 'is_other',
]


# ── Math ─────────────────────────────────────────────────────────────────

def _sigmoid(z):
    if z >= 0:
        return 1.0 / (1.0 + math.exp(-z))
    ex = math.exp(z)
    return ex / (1.0 + ex)


def _dot(weights, values):
    return sum(w * v for w, v in zip(weights, values))


def train_logistic(X, y, epochs=400, lr=0.3, l2=0.01):
    """Batch gradient descent. Returns (weights, bias)."""
    if not X:
        return [], 0.0
    n = len(X)
    d = len(X[0])
    weights = [0.0] * d
    bias = 0.0
    for _ in range(max(1, int(epochs))):
        grad_w = [0.0] * d
        grad_b = 0.0
        for xi, yi in zip(X, y):
            error = _sigmoid(_dot(weights, xi) + bias) - yi
            for j in range(d):
                grad_w[j] += error * xi[j]
            grad_b += error
        for j in range(d):
            weights[j] -= lr * (grad_w[j] / n + l2 * weights[j])
        bias -= lr * (grad_b / n)
    return weights, bias


def _standardize_fit(X):
    d = len(X[0])
    n = len(X)
    means = [0.0] * d
    for row in X:
        for j in range(d):
            means[j] += row[j]
    means = [m / n for m in means]
    stds = [0.0] * d
    for row in X:
        for j in range(d):
            stds[j] += (row[j] - means[j]) ** 2
    stds = [max(1e-6, math.sqrt(s / n)) for s in stds]
    return means, stds


def _standardize(row, means, stds):
    return [(v - m) / s for v, m, s in zip(row, means, stds)]


def _accuracy(X, y, weights, bias):
    if not X:
        return 0.0
    correct = 0
    for xi, yi in zip(X, y):
        predicted = 1 if _sigmoid(_dot(weights, xi) + bias) >= 0.5 else 0
        correct += 1 if predicted == yi else 0
    return round(correct / len(X), 3)


def _fit_and_save(name, features, X, y, meta=None):
    if len(X) < 2 or len({*y}) < 2:
        return None
    split = max(1, int(len(X) * 0.8))
    train_X, train_y = X[:split], y[:split]
    test_X, test_y = X[split:], y[split:]
    means, stds = _standardize_fit(train_X)
    train_X = [_standardize(row, means, stds) for row in train_X]
    weights, bias = train_logistic(train_X, train_y)
    accuracy = _accuracy(
        [_standardize(row, means, stds) for row in test_X], test_y, weights, bias
    ) if test_X else _accuracy(train_X, train_y, weights, bias)
    payload = {
        'features': list(features),
        'weights': weights,
        'bias': bias,
        'means': means,
        'stds': stds,
    }
    full_meta = {
        'samples': len(X),
        'positives': int(sum(y)),
        'accuracy': accuracy,
        'features': list(features),
        'trained_at': timezone.now().isoformat(),
    }
    full_meta.update(meta or {})
    artifact, _ = ModelArtifact.objects.update_or_create(
        name=name,
        defaults={
            'weights': payload,
            'meta': full_meta,
            'samples': len(X),
        },
    )
    return artifact


def load_artifact(name):
    return ModelArtifact.objects.filter(name=name).first()


def artifact_probability(name, values, artifact=None):
    artifact = artifact or load_artifact(name)
    if artifact is None:
        return None
    payload = artifact.weights or {}
    features = payload.get('features') or []
    weights = payload.get('weights') or []
    means = payload.get('means') or []
    stds = payload.get('stds') or []
    if not features or len(weights) != len(features):
        return None
    row = [float(values.get(feature, 0.0)) for feature in features]
    row = _standardize(row, means, stds)
    return _sigmoid(_dot(weights, row) + float(payload.get('bias', 0.0)))


# ── Join features ────────────────────────────────────────────────────────

def join_context(user, now=None):
    now = now or timezone.now()
    profile = UserProfile.objects.filter(user=user).first()
    favorites = {
        s.strip().lower()
        for s in ((profile.favorite_sports if profile else '') or '').split(',')
        if s.strip()
    }
    city = ((profile.location if profile else '') or '').split(',')[0].strip().lower()

    sport_joins = defaultdict(int)
    for row in (
        MatchParticipant.objects.filter(user=user)
        .values('match__sport').annotate(n=Count('id'))
    ):
        sport_joins[(row['match__sport'] or '').lower()] += row['n']
    total_joins = sum(sport_joins.values())

    exposures = {
        row['match_id']: row['n']
        for row in RecommendationExposure.objects.filter(user=user)
        .values('match_id').annotate(n=Count('id'))
    }

    return {
        'favorites': favorites,
        'city': city,
        'sport_joins': dict(sport_joins),
        'total_joins': total_joins,
        'exposures': exposures,
        'cf': co_participation_scores(user, now=now),
        'now': now,
    }


def build_join_features(match, context, organizer_reliability=100):
    now = context['now']
    favorites = context['favorites']
    city = context['city']

    if not favorites:
        sport_fit = 0.5
    else:
        sport_fit = 1.0 if match.sport.lower() in favorites else 0.0

    location = (match.location or '').lower()
    if not city:
        city_fit = 0.5
    elif city in location:
        city_fit = 1.0
    else:
        city_fit = 0.2

    hours = (match.date_time - now).total_seconds() / 3600.0
    if hours <= 24:
        hours_fit = 1.0
    elif hours <= 48:
        hours_fit = 0.8
    elif hours <= 168:
        hours_fit = 0.5
    else:
        hours_fit = 0.2

    spots = max(0, match.max_players - match.current_players)
    if spots <= 3:
        scarcity_fit = 1.0
    elif spots <= 5:
        scarcity_fit = 0.7
    elif spots <= 10:
        scarcity_fit = 0.4
    else:
        scarcity_fit = 0.15

    skill_fit = 1.0 if getattr(match, 'skill_level', 'any') == 'any' else 0.6
    price = float(match.price or 0)
    price_fit = 1.0 if price <= 0 else max(0.1, min(1.0, 1.0 - price / 1000.0))

    organizer_profile = getattr(match.organizer, 'profile', None)
    premium = 1.0 if organizer_profile and organizer_profile.premium_active else 0.0

    local_dt = timezone.localtime(match.date_time)
    hour_angle = (local_dt.hour + local_dt.minute / 60.0) / 24.0 * 2 * math.pi
    total_joins = max(1, context['total_joins'])
    sport_join_rate = min(1.0, context['sport_joins'].get(
        match.sport.lower(), 0) / total_joins) if context['total_joins'] else 0.0

    return {
        'sport_fit': sport_fit,
        'city_fit': city_fit,
        'hours_fit': hours_fit,
        'scarcity_fit': scarcity_fit,
        'skill_fit': skill_fit,
        'price_fit': price_fit,
        'organizer_premium': premium,
        'organizer_reliability': max(0.0, min(1.0, organizer_reliability / 100.0)),
        'cf_score': float(context['cf'].get(match.id, 0.0)),
        'prior_exposures': min(1.0, context['exposures'].get(match.id, 0) / 10.0),
        'sport_join_rate': sport_join_rate,
        'weekend': 1.0 if local_dt.weekday() >= 5 else 0.0,
        'hour_sin': (math.sin(hour_angle) + 1) / 2,
        'hour_cos': (math.cos(hour_angle) + 1) / 2,
    }


def join_propensity(features, artifact=None):
    return artifact_probability('join_propensity', features, artifact=artifact)


# ── Churn features ───────────────────────────────────────────────────────

def _week_start(value):
    d = value.date() if hasattr(value, 'date') else value
    return d - timedelta(days=d.weekday())


def _streak_as_of(user, as_of, weeks=12):
    start = as_of - timedelta(weeks=weeks)
    dates = []
    dates += list(MatchParticipant.objects.filter(
        user=user, joined_at__gte=start, joined_at__lte=as_of,
    ).values_list('joined_at', flat=True))
    dates += list(Match.objects.filter(
        organizer=user, created_at__gte=start, created_at__lte=as_of,
    ).values_list('created_at', flat=True))
    dates += list(VenueBooking.objects.filter(
        booked_by=user, created_at__gte=start, created_at__lte=as_of,
    ).values_list('created_at', flat=True))
    seen = {_week_start(d) for d in dates}
    if not seen:
        return 0
    current = _week_start(as_of)
    cursor = current if current in seen else current - timedelta(weeks=1)
    if cursor not in seen:
        return 0
    streak = 0
    while cursor in seen:
        streak += 1
        cursor -= timedelta(weeks=1)
    return streak


def churn_features(user, as_of=None):
    as_of = as_of or timezone.now()
    profile = UserProfile.objects.filter(user=user).first()

    last_event = AnalyticsEvent.objects.filter(
        user=user, created_at__lte=as_of,
    ).order_by('-created_at').values_list('created_at', flat=True).first()
    if last_event is None:
        last_event = MatchParticipant.objects.filter(
            user=user, joined_at__lte=as_of,
        ).order_by('-joined_at').values_list('joined_at', flat=True).first()
    days_since = (as_of - last_event).days if last_event else 60

    events = AnalyticsEvent.objects.filter(user=user, created_at__lte=as_of)
    sessions_7d = events.filter(
        created_at__gte=as_of - timedelta(days=7)
    ).exclude(session_id='').values('session_id').distinct().count()
    sessions_28d = events.filter(
        created_at__gte=as_of - timedelta(days=28)
    ).exclude(session_id='').values('session_id').distinct().count()

    joined_28d = MatchParticipant.objects.filter(
        user=user, joined_at__gte=as_of - timedelta(days=28), joined_at__lte=as_of,
    ).count()
    hosted_28d = Match.objects.filter(
        organizer=user, created_at__gte=as_of - timedelta(days=28), created_at__lte=as_of,
    ).count()

    rating_avg = PlayerRating.objects.filter(rated_user=user).aggregate(
        avg=Avg('rating'))['avg']
    reliability_score = 100
    if profile:
        reliability_score -= 15 * max(0, profile.no_show_count)
        reliability_score -= 10 * max(0, profile.host_cancel_count)
    if rating_avg is not None:
        reliability_score += (float(rating_avg) - 3) * 10
    reliability_score = max(0, min(100, reliability_score))

    upcoming = MatchParticipant.objects.filter(
        user=user, match__is_active=True,
        match__date_time__gte=as_of,
        match__date_time__lte=as_of + timedelta(days=7),
    ).count()

    return {
        'days_since_active': min(1.0, max(0, days_since) / 60.0),
        'sessions_7d': min(1.0, sessions_7d / 10.0),
        'sessions_28d': min(1.0, sessions_28d / 30.0),
        'matches_joined_28d': min(1.0, joined_28d / 10.0),
        'matches_hosted_28d': min(1.0, hosted_28d / 5.0),
        'streak_weeks': min(1.0, _streak_as_of(user, as_of) / 12.0),
        'no_shows': min(1.0, (profile.no_show_count if profile else 0) / 5.0),
        'is_premium': 1.0 if profile and profile.premium_active else 0.0,
        'reliability': reliability_score / 100.0,
        'upcoming_matches': min(1.0, upcoming / 5.0),
    }


def churn_probability(user, as_of=None):
    if load_artifact('churn') is None:
        return None
    return artifact_probability('churn', churn_features(user, as_of=as_of))


# ── Fill features ────────────────────────────────────────────────────────

def fill_features(match, organizer_reliability=100):
    if isinstance(organizer_reliability, dict):
        organizer_reliability = organizer_reliability.get('score', 100)
    lead_days = max(0.0, (match.date_time - match.created_at).total_seconds() / 86400.0)
    local_dt = timezone.localtime(match.date_time)
    hour_angle = (local_dt.hour + local_dt.minute / 60.0) / 24.0 * 2 * math.pi
    sport = (match.sport or '').lower()
    return {
        'lead_days': min(2.0, lead_days / 14.0),
        'capacity': min(1.0, (match.max_players or 0) / 30.0),
        'price_scaled': min(1.0, float(match.price or 0) / 1000.0),
        'min_players': min(1.0, (match.min_players or 0) / 30.0),
        'weekend': 1.0 if local_dt.weekday() >= 5 else 0.0,
        'hour_sin': (math.sin(hour_angle) + 1) / 2,
        'hour_cos': (math.cos(hour_angle) + 1) / 2,
        'organizer_reliability': max(0.0, min(1.0, organizer_reliability / 100.0)),
        'is_soccer': 1.0 if sport == 'soccer' else 0.0,
        'is_basketball': 1.0 if sport == 'basketball' else 0.0,
        'is_tennis': 1.0 if sport == 'tennis' else 0.0,
        'is_volleyball': 1.0 if sport == 'volleyball' else 0.0,
        'is_cricket': 1.0 if sport == 'cricket' else 0.0,
        'is_esports': 1.0 if sport == 'esports' else 0.0,
        'is_other': 1.0 if sport == 'other' else 0.0,
    }


def fill_probability(match, organizer_reliability=None):
    """Blend the learned attribute model with live fill progress (0..1)."""
    if organizer_reliability is None:
        from .reliability import reliability
        organizer_reliability = reliability(match.organizer)['score']

    max_players = max(1, match.max_players or 1)
    fill_ratio = min(1.0, max(0.0, match.current_players / max_players))
    heuristic = 0.10 + 0.72 * fill_ratio
    hours = (match.date_time - timezone.now()).total_seconds() / 3600.0
    if hours <= 24:
        heuristic += 0.12
    elif hours <= 72:
        heuristic += 0.05
    if float(match.price or 0) <= 0:
        heuristic += 0.04
    heuristic = max(0.0, min(1.0, heuristic))

    modeled = artifact_probability('fill_probability', fill_features(
        match, organizer_reliability))
    if modeled is None:
        return round(heuristic, 3)
    return round(max(0.0, min(1.0, 0.25 * modeled + 0.75 * heuristic)), 3)


def model_status():
    return {
        artifact.name: {
            'samples': artifact.samples,
            'positives': (artifact.meta or {}).get('positives'),
            'accuracy': (artifact.meta or {}).get('accuracy'),
            'trained_at': artifact.trained_at.isoformat(),
        }
        for artifact in ModelArtifact.objects.all()
    }


# ── Training ─────────────────────────────────────────────────────────────

def _join_dataset(limit=5000, now=None):
    now = now or timezone.now()
    cutoff = now - timedelta(hours=24)
    exposures = list(
        RecommendationExposure.objects.filter(created_at__lte=cutoff)
        .select_related('user', 'match').order_by('created_at')[:limit]
    )
    if not exposures:
        return [], []

    user_ids = {e.user_id for e in exposures}
    match_ids = {e.match_id for e in exposures}
    joined = {
        (row['user_id'], row['match_id']): row['joined_at']
        for row in MatchParticipant.objects.filter(
            user_id__in=user_ids, match_id__in=match_ids,
        ).values('user_id', 'match_id', 'joined_at')
    }

    X, y = [], []
    for exposure in exposures:
        joined_at = joined.get((exposure.user_id, exposure.match_id))
        label = 1 if (
            joined_at is not None
            and exposure.created_at - timedelta(hours=1) <= joined_at
            <= exposure.created_at + timedelta(hours=24)
        ) else 0
        features = exposure.features or {}
        if not all(feature in features for feature in JOIN_FEATURES):
            continue
        X.append([float(features[feature]) for feature in JOIN_FEATURES])
        y.append(label)
    return X, y


def train_join_model(min_samples=JOIN_MIN_SAMPLES, min_positives=JOIN_MIN_POSITIVES,
                     limit=5000, now=None):
    X, y = _join_dataset(limit=limit, now=now)
    positives = sum(y)
    ready = len(X) >= min_samples and positives >= min_positives
    result = {
        'model': 'join_propensity',
        'samples': len(X),
        'positives': positives,
        'min_samples': min_samples,
        'min_positives': min_positives,
        'ready': ready,
        'trained': False,
    }
    if not ready:
        return result
    artifact = _fit_and_save('join_propensity', JOIN_FEATURES, X, y, {
        'threshold': {'min_samples': min_samples, 'min_positives': min_positives},
    })
    result['trained'] = artifact is not None
    if artifact:
        result['accuracy'] = (artifact.meta or {}).get('accuracy')
    return result


def train_churn_model(min_users=CHURN_MIN_USERS, now=None):
    now = now or timezone.now()
    window_start = now - timedelta(days=42)
    cutoff = now - timedelta(days=14)

    active_before = set(
        AnalyticsEvent.objects.filter(
            user__isnull=False, created_at__gte=window_start, created_at__lte=cutoff,
        ).values_list('user_id', flat=True)
    )
    X, y = [], []
    for user in User.objects.filter(id__in=active_before):
        prior_count = AnalyticsEvent.objects.filter(
            user=user, created_at__gte=window_start, created_at__lte=cutoff,
        ).count()
        if prior_count < 3:
            continue
        features = churn_features(user, as_of=cutoff)
        label = 1 if AnalyticsEvent.objects.filter(
            user=user, created_at__gt=cutoff, created_at__lte=now,
        ).exists() else 0
        X.append([float(features[f]) for f in CHURN_FEATURES])
        y.append(label)

    ready = len(X) >= min_users
    result = {
        'model': 'churn',
        'samples': len(X),
        'positives': int(sum(y)),
        'min_users': min_users,
        'ready': ready,
        'trained': False,
    }
    if not ready:
        return result
    artifact = _fit_and_save('churn', CHURN_FEATURES, X, y, {
        'threshold': {'min_users': min_users},
        'window_days': 42,
    })
    result['trained'] = artifact is not None
    if artifact:
        result['accuracy'] = (artifact.meta or {}).get('accuracy')
    return result


def train_fill_model(min_matches=FILL_MIN_MATCHES, now=None, limit=5000):
    now = now or timezone.now()
    matches = list(
        Match.objects.filter(date_time__lt=now - timedelta(hours=1))
        .select_related('organizer').order_by('-date_time')[:limit]
    )

    from .reliability import organizer_reliability_map
    rel_map = organizer_reliability_map(matches) if matches else {}

    X, y = [], []
    for match in matches:
        if match.max_players <= 0:
            continue
        features = fill_features(match, rel_map.get(match.organizer_id, {'score': 100}))
        label = 1 if match.current_players >= match.max_players * 0.8 else 0
        X.append([float(features[f]) for f in FILL_FEATURES])
        y.append(label)

    ready = len(X) >= min_matches
    result = {
        'model': 'fill_probability',
        'samples': len(X),
        'positives': int(sum(y)),
        'min_matches': min_matches,
        'ready': ready,
        'trained': False,
    }
    if not ready:
        return result
    artifact = _fit_and_save('fill_probability', FILL_FEATURES, X, y, {
        'threshold': {'min_matches': min_matches},
        'label': 'filled at least 80% of capacity',
    })
    result['trained'] = artifact is not None
    if artifact:
        result['accuracy'] = (artifact.meta or {}).get('accuracy')
    return result
