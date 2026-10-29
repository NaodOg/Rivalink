"""Retention engine: ranking, streaks, next-best-action and automated nudges.

The base layer is deliberately explainable. When enough data exists, learned
models (join propensity, churn, fill probability) blend in automatically; if not,
every function falls back to rules. All optimizations are capped by notification
frequency limits and quiet hours.
"""
from datetime import timedelta
from random import Random

from django.contrib.auth.models import User
from django.db.models import F, Max
from django.utils import timezone

from .bandit import (
    copy_variant, notification_allowed, pick, record_notification_sent,
    send_time_allows, send_window,
)
from .experiments import experiment_payload, ranking_config
from .ml import (
    build_join_features, churn_probability, fill_probability, join_context,
    join_propensity, load_artifact, model_status,
)
from .models import (
    AnalyticsEvent, LeagueFixture, Match, MatchParticipant, MatchResult,
    Notification, RecommendationExposure, UserProfile, VenueBooking,
)
from .push import notify
from .reliability import organizer_reliability_map, reliability
from .serializers import match_summary


# ── Activity + streaks ───────────────────────────────────────────────────

def _week_start(dt):
    d = dt.date() if hasattr(dt, 'date') else dt
    return d - timedelta(days=d.weekday())


def activity_weeks(user, weeks=12):
    now = timezone.now()
    start = now - timedelta(weeks=weeks)
    dates = []
    dates += list(MatchParticipant.objects.filter(
        user=user, joined_at__gte=start).values_list('joined_at', flat=True))
    dates += list(Match.objects.filter(
        organizer=user, created_at__gte=start).values_list('created_at', flat=True))
    dates += list(VenueBooking.objects.filter(
        booked_by=user, created_at__gte=start).values_list('created_at', flat=True))
    return {_week_start(d) for d in dates}


def user_streak(user, weeks=12):
    seen = activity_weeks(user, weeks)
    if not seen:
        return {'weeks': 0, 'active_this_week': False}
    current = _week_start(timezone.now())
    last = current - timedelta(weeks=1)
    active_this_week = current in seen
    cursor = current if active_this_week else last
    if cursor not in seen:
        return {'weeks': 0, 'active_this_week': False}
    streak = 0
    while cursor in seen:
        streak += 1
        cursor -= timedelta(weeks=1)
    return {'weeks': streak, 'active_this_week': active_this_week}


# ── At-risk scoring ──────────────────────────────────────────────────────

def at_risk_score(user):
    now = timezone.now()
    last_event = AnalyticsEvent.objects.filter(user=user).order_by('-created_at').values_list(
        'created_at', flat=True).first()
    if last_event is None:
        last_event = MatchParticipant.objects.filter(user=user).order_by('-joined_at').values_list(
            'joined_at', flat=True).first()
    days_inactive = (now - last_event).days if last_event else 30

    sessions_7d = AnalyticsEvent.objects.filter(
        user=user, name='screen_viewed', created_at__gte=now - timedelta(days=7)
    ).values('session_id').distinct().count()
    upcoming = MatchParticipant.objects.filter(
        user=user, match__is_active=True, match__date_time__gte=now).count()

    rules_score = days_inactive * 10 + max(0, 7 - sessions_7d) * 6 - upcoming * 15
    rules_score = max(0, min(100, rules_score))

    model_probability = churn_probability(user)
    if model_probability is None:
        score = rules_score
        source = 'rules'
    else:
        score = round(0.5 * rules_score + 0.5 * model_probability * 100)
        source = 'model'

    score = max(0, min(100, score))
    label = 'high' if score >= 60 else ('medium' if score >= 30 else 'low')
    return {
        'score': score,
        'label': label,
        'days_inactive': days_inactive,
        'sessions_7d': sessions_7d,
        'upcoming_matches': upcoming,
        'model_probability': round(model_probability, 3) if model_probability is not None else None,
        'source': source,
    }


# ── Personalized match ranking ───────────────────────────────────────────

def _reason_chips(match, features, organizer_rel):
    reasons = []
    if features['sport_fit'] >= 1:
        reasons.append('Your sport')
    if features['city_fit'] >= 1:
        reasons.append('Near you')
    hours = (match.date_time - timezone.now()).total_seconds() / 3600.0
    if hours <= 24:
        reasons.append('Starts soon')
    elif hours <= 48:
        reasons.append('This week')
    spots = match.max_players - match.current_players
    if 0 < spots <= 3:
        reasons.append(f'Only {spots} spot{"s" if spots != 1 else ""} left')
    if organizer_rel >= 90:
        reasons.append('Reliable organizer')
    if features['cf_score'] >= 0.3:
        reasons.append('Players like you joined')
    if not reasons:
        reasons.append(f'{match.sport.title()} match')
    return reasons


def recommend_matches(user, limit=10, surface='recommendations', log=True):
    """Rank upcoming matches with reasons, exploration and optional learning."""
    limit = max(1, int(limit))
    now = timezone.now()

    joined = set(MatchParticipant.objects.filter(user=user).values_list('match_id', flat=True))
    candidates = list(
        Match.objects.filter(
            is_active=True,
            date_time__gte=now,
            current_players__lt=F('max_players'),
        ).exclude(id__in=joined).exclude(organizer=user)
        .select_related('organizer', 'organizer__profile')[:300]
    )
    if not candidates:
        return []

    context = join_context(user, now=now)
    rel_map = organizer_reliability_map(candidates)
    join_artifact = load_artifact('join_propensity')
    config = ranking_config(user)
    weights = {
        'sport': config['sport'],
        'city': config['city'],
        'urgency': config['urgency'],
        'scarcity': config['scarcity'],
        'social': config['social'],
        'quality': config['quality'],
    }

    scored = []
    for match in candidates:
        organizer_rel = rel_map.get(match.organizer_id, {}).get('score', 100)
        features = build_join_features(match, context, organizer_rel)

        rules_score = 100.0 * (
            weights['sport'] * features['sport_fit']
            + weights['city'] * features['city_fit']
            + weights['urgency'] * features['hours_fit']
            + weights['scarcity'] * features['scarcity_fit']
            + weights['social'] * features['cf_score']
            + weights['quality'] * features['organizer_reliability']
        )
        model_probability = join_propensity(features, artifact=join_artifact)
        if model_probability is None:
            final_score = rules_score
        else:
            final_score = 0.6 * rules_score + 0.4 * model_probability * 100.0

        reasons = _reason_chips(match, features, organizer_rel)
        scored.append({
            'score': round(final_score, 2),
            'date': match.date_time,
            'match': match,
            'features': features,
            'reasons': reasons,
            'model_probability': round(model_probability, 4) if model_probability is not None else None,
        })

    scored.sort(key=lambda row: (-row['score'], row['date']))

    explore_slots = min(
        max(0, len(scored) - 1),
        int(round(limit * config['exploration'])),
    )
    if explore_slots and len(scored) > limit:
        keep = max(1, limit - explore_slots)
        selected = scored[:keep]
        pool = scored[keep:]
        rng = Random(f'{getattr(user, "id", 0)}-{timezone.localdate().isoformat()}')
        picks = rng.sample(pool, min(explore_slots, len(pool)))
        for pick_row in picks:
            pick_row = dict(pick_row)
            pick_row['reasons'] = ['Something new'] + [
                r for r in pick_row['reasons'] if r != 'Something new'
            ]
            selected.append(pick_row)
        if len(selected) < limit:
            chosen_ids = {row['match'].id for row in selected}
            for row in scored:
                if len(selected) >= limit:
                    break
                if row['match'].id not in chosen_ids:
                    selected.append(row)
                    chosen_ids.add(row['match'].id)
    else:
        selected = scored[:limit]

    data = []
    for row in selected:
        match = row['match']
        summary = match_summary(match)
        summary['match_score'] = row['score']
        summary['reasons'] = row['reasons']
        summary['reason'] = row['reasons'][0] if row['reasons'] else ''
        summary['recommendation_variant'] = config['variant']
        if row['model_probability'] is not None:
            summary['join_probability'] = row['model_probability']
        data.append(summary)

    if log and data:
        for row in selected:
            try:
                RecommendationExposure.objects.create(
                    user=user,
                    match=row['match'],
                    surface=surface,
                    variant=config['variant'],
                    score=row['score'],
                    features=row['features'],
                )
            except Exception:
                pass

    return data


# ── Next best action ─────────────────────────────────────────────────────

def next_best_action(user):
    now = timezone.now()

    # 1. Joined match starting within 24h.
    p = MatchParticipant.objects.filter(
        user=user, match__is_active=True,
        match__date_time__gte=now, match__date_time__lte=now + timedelta(hours=24),
    ).select_related('match').order_by('match__date_time').first()
    if p:
        hours = max(1, int((p.match.date_time - now).total_seconds() // 3600))
        return {
            'type': 'match_soon',
            'headline': f'"{p.match.title}" starts in {hours}h',
            'message': f'{p.match.location}. Confirm your spot and check the chat.',
            'cta_label': 'View match',
            'route': 'match',
            'match_id': p.match_id,
        }

    # 2. Hosted match with open spots within 48h.
    m = Match.objects.filter(
        organizer=user, is_active=True, current_players__lt=F('max_players'),
        date_time__gte=now, date_time__lte=now + timedelta(hours=48),
    ).order_by('date_time').first()
    if m:
        spots = m.max_players - m.current_players
        return {
            'type': 'fill_match',
            'headline': f'Your match needs {spots} more {"player" if spots == 1 else "players"}',
            'message': f'"{m.title}" kicks off soon. Invite players from your squad.',
            'cta_label': 'Open match',
            'route': 'match',
            'match_id': m.id,
            'fill_probability': fill_probability(m),
        }

    # 3. Premium expiring soon.
    profile = UserProfile.objects.filter(user=user).first()
    if profile and profile.premium_active and profile.premium_expires and \
            profile.premium_expires <= now + timedelta(days=7):
        days = max(1, (profile.premium_expires - now).days)
        return {
            'type': 'premium_expiry',
            'headline': f'Premium expires in {days} day{"s" if days != 1 else ""}',
            'message': 'Renew to keep unlimited hosting, teams, and league access.',
            'cta_label': 'Renew',
            'route': 'premium',
        }

    # 4. Streak at risk.
    streak = user_streak(user)
    if streak['weeks'] >= 2 and not streak['active_this_week']:
        return {
            'type': 'streak_risk',
            'headline': f'Keep your {streak["weeks"]}-week streak alive',
            'message': 'Join or host one match this week to keep it going.',
            'cta_label': 'Find a match',
            'route': 'explore',
        }

    # 5. Win-back.
    risk = at_risk_score(user)
    if risk['days_inactive'] >= 7:
        rec = recommend_matches(user, 1, log=False)
        return {
            'type': 'win_back',
            'headline': 'Your next game is waiting',
            'message': (f'"{rec[0]["title"]}" is open near you.'
                        if rec else 'There are games near you this week.'),
            'cta_label': 'See matches',
            'route': 'match' if rec else 'explore',
            'match_id': rec[0]['id'] if rec else None,
        }

    # 6. Discover a recommended match.
    rec = recommend_matches(user, 1, log=False)
    if rec:
        return {
            'type': 'discover',
            'headline': rec[0]['title'],
            'message': f'{rec[0]["location"]} · {rec[0]["sport"]}',
            'cta_label': 'View match',
            'route': 'match',
            'match_id': rec[0]['id'],
        }

    # 7. Fallback.
    return {
        'type': 'host_match',
        'headline': 'Start a game this week',
        'message': 'Host a match and let players nearby join.',
        'cta_label': 'Host a match',
        'route': 'host',
    }


def engagement_status(user):
    return {
        'streak': user_streak(user),
        'at_risk': at_risk_score(user),
        'next_action': next_best_action(user),
        'recommended': recommend_matches(user, 3, log=False),
        'reliability': reliability(user),
        'models': model_status(),
        'experiments': experiment_payload(user),
    }


# ── Automated nudges (cron) ──────────────────────────────────────────────

def notify_once(user, title, message, match=None, notification_type='general',
                dedupe_hours=24, critical=False, kind='engagement',
                variant='', arm=''):
    since = timezone.now() - timedelta(hours=dedupe_hours)
    qs = Notification.objects.filter(user=user, title=title, created_at__gte=since)
    if match is not None:
        qs = qs.filter(related_match=match)
    if qs.exists():
        return False
    if not notification_allowed(user, critical=critical):
        return False

    chosen_variant = variant or copy_variant(user, kind)
    chosen_arm = arm or send_window()
    notify(user, notification_type, title, message, match=match)
    record_notification_sent(user, kind, chosen_variant, chosen_arm)
    return True


def send_fixture_reminders(hours=24):
    now = timezone.now()
    sent = 0
    fixtures = LeagueFixture.objects.filter(
        status='scheduled', kickoff__gte=now, kickoff__lte=now + timedelta(hours=hours),
    ).select_related('league', 'home_team', 'away_team')
    for fixture in fixtures:
        title = f'Fixture soon: {fixture.home_team.name} vs {fixture.away_team.name}'
        message = (f'{fixture.league.name} · Round {fixture.round_number}. '
                   f'{fixture.kickoff:%a %H:%M}.')
        for team in (fixture.home_team, fixture.away_team):
            if notify_once(team.owner, title, message, dedupe_hours=12, critical=True,
                           kind='fixture_reminder'):
                sent += 1
    return sent


def fill_assistant(hours=48, limit_per_match=10, respect_windows=False):
    now = timezone.now()
    sent = 0
    matches = list(Match.objects.filter(
        is_active=True, current_players__lt=F('max_players'),
        date_time__gte=now, date_time__lte=now + timedelta(hours=hours),
    ).select_related('organizer')[:50])
    if not matches:
        return 0

    active_since = now - timedelta(days=14)
    active_ids = set(
        AnalyticsEvent.objects.filter(created_at__gte=active_since,
                                      user__isnull=False)
        .values_list('user_id', flat=True)
    )
    users = {
        user.id: user for user in User.objects.filter(id__in=active_ids)
    }
    participants = set(MatchParticipant.objects.filter(
        match__in=matches).values_list('match_id', 'user_id'))
    profiles = {
        profile.user_id: profile
        for profile in UserProfile.objects.filter(user_id__in=active_ids)
    }

    # Matches least likely to fill get help first.
    rel_map = organizer_reliability_map(matches)
    matches.sort(key=lambda m: fill_probability(
        m, rel_map.get(m.organizer_id, {}).get('score', 100)))

    for match in matches:
        candidates = []
        for uid in active_ids:
            if (match.id, uid) in participants or uid == match.organizer_id:
                continue
            profile = profiles.get(uid)
            if profile is None:
                continue
            sports = (profile.favorite_sports or '').lower()
            if sports and match.sport.lower() not in sports:
                continue
            candidates.append(uid)
        for uid in candidates[:limit_per_match]:
            user = users.get(uid)
            if user is None:
                continue
            if respect_windows and not send_time_allows(user, now):
                continue
            if not notification_allowed(user, now):
                continue
            variant = copy_variant(user, 'fill')
            title = 'Players needed nearby'
            spots = match.max_players - match.current_players
            message = pick(
                variant,
                f'"{match.title}" has {spots} open spots. '
                f'{match.location} · {match.date_time:%a %H:%M}.',
                f'A spot just opened in "{match.title}" — {spots} left. '
                f'{match.location} · {match.date_time:%a %H:%M}.',
            )
            if notify_once(user, title, message, match=match, dedupe_hours=24,
                           kind='fill', variant=variant):
                sent += 1
    return sent


def _user(uid):
    return User.objects.filter(id=uid).first()


def win_back(days_min=3, days_max=30, limit=200, respect_windows=False):
    now = timezone.now()
    cutoff_recent = now - timedelta(days=days_min)
    cutoff_old = now - timedelta(days=days_max)
    rows = (
        AnalyticsEvent.objects.filter(user__isnull=False)
        .values('user_id').annotate(last=Max('created_at'))
        .filter(last__lte=cutoff_recent, last__gte=cutoff_old)
        .order_by('last')[:limit]
    )
    sent = 0
    for row in rows:
        user = _user(row['user_id'])
        if user is None:
            continue
        if not MatchParticipant.objects.filter(user=user).exists():
            continue
        if respect_windows and not send_time_allows(user, now):
            continue
        risk = at_risk_score(user)
        if risk['days_inactive'] < 7 and risk['score'] < 30:
            continue
        action = next_best_action(user)
        variant = copy_variant(user, 'win_back')
        title = 'We saved your spot'
        message = pick(
            variant,
            f'{action["headline"]}. {action["message"]}',
            f'{action["headline"]} — pick up where you left off. {action["message"]}',
        )
        if notify_once(
            user,
            title,
            message,
            dedupe_hours=24 * 7,
            kind='win_back',
            variant=variant,
        ):
            sent += 1
    return sent


def premium_expiry_nudges(days=3, respect_windows=False):
    now = timezone.now()
    sent = 0
    profiles = UserProfile.objects.filter(
        is_premium=True, premium_expires__gt=now,
        premium_expires__lte=now + timedelta(days=days),
    ).select_related('user')
    for profile in profiles:
        if respect_windows and not send_time_allows(profile.user, now):
            continue
        variant = copy_variant(profile.user, 'premium')
        title = 'Premium is expiring'
        days_left = max(1, (profile.premium_expires - now).days)
        message = pick(
            variant,
            f'Your Rivalink Premium ends in {days_left} day(s). '
            'Renew to keep unlimited hosting and leagues.',
            f'{days_left} day(s) of Premium left. Renew now so your hosting '
            'and league access do not pause.',
        )
        if notify_once(
            profile.user,
            title,
            message,
            dedupe_hours=24,
            kind='premium',
            variant=variant,
        ):
            sent += 1
    return sent


def streak_nudges(limit=300, respect_windows=False):
    now = timezone.now()
    active_since = now - timedelta(days=7)
    recently_active = set(
        AnalyticsEvent.objects.filter(created_at__gte=active_since, user__isnull=False)
        .values_list('user_id', flat=True)
    )
    sent = 0
    for row in (MatchParticipant.objects.values('user_id')
                .annotate(n=Max('joined_at')).order_by('-n')[:limit]):
        uid = row['user_id']
        if not uid:
            continue
        user = _user(uid)
        if user is None:
            continue
        streak = user_streak(user)
        if streak.get('weeks', 0) < 2 or uid in recently_active:
            continue
        if respect_windows and not send_time_allows(user, now):
            continue
        variant = copy_variant(user, 'streak')
        title = 'Your streak is on the line'
        message = pick(
            variant,
            f'You are on a {streak["weeks"]}-week streak. '
            'Play once this week to keep it.',
            f'{streak["weeks"]} weeks in a row — one game this week keeps the run alive.',
        )
        if notify_once(
            user,
            title,
            message,
            dedupe_hours=24 * 7,
            kind='streak',
            variant=variant,
        ):
            sent += 1
    return sent


def post_match_rematch(hours=48, respect_windows=False):
    """24–48h after a confirmed result, invite players into their next game."""
    now = timezone.now()
    sent = 0
    results = MatchResult.objects.filter(
        status='confirmed',
        confirmed_at__gte=now - timedelta(hours=hours),
        confirmed_at__lte=now - timedelta(hours=24),
    ).select_related('match').order_by('confirmed_at')[:100]

    for result in results:
        participant_ids = list(
            MatchParticipant.objects.filter(match=result.match)
            .values_list('user_id', flat=True)
        )
        participant_ids.append(result.match.organizer_id)
        for uid in dict.fromkeys(participant_ids):
            user = _user(uid)
            if user is None:
                continue
            if respect_windows and not send_time_allows(user, now):
                continue
            rec = recommend_matches(user, 1, log=False)
            variant = copy_variant(user, 'rematch')
            title = 'Run it back?'
            if rec:
                message = pick(
                    variant,
                    f'"{result.match.title}" is in the books. '
                    f'Next up: "{rec[0]["title"]}" — {rec[0]["location"]}.',
                    f'Good game. "{rec[0]["title"]}" is open — '
                    f'{rec[0]["location"]}. Run it back?',
                )
            else:
                message = pick(
                    variant,
                    f'"{result.match.title}" is in the books. '
                    'Host a rematch or find your next game.',
                    'That was a good one. Gather the squad for a rematch this week.',
                )
            if notify_once(
                user, title, message,
                match=result.match,
                dedupe_hours=48, kind='rematch', variant=variant,
            ):
                sent += 1
    return sent


def weekly_recap(limit=300, force=False, respect_windows=False):
    now = timezone.now()
    if not force and timezone.localtime(now).weekday() != 0:
        return 0

    week_ago = now - timedelta(days=7)
    user_ids = list(
        MatchParticipant.objects.filter(joined_at__gte=week_ago)
        .values_list('user_id', flat=True).distinct()[:limit]
    )
    sent = 0
    for uid in user_ids:
        user = _user(uid)
        if user is None:
            continue
        played = MatchParticipant.objects.filter(
            user=user, joined_at__gte=week_ago).count()
        hosted = Match.objects.filter(
            organizer=user, created_at__gte=week_ago).count()
        if played + hosted == 0:
            continue
        if respect_windows and not send_time_allows(user, now):
            continue
        streak = user_streak(user)
        upcoming = MatchParticipant.objects.filter(
            user=user, match__is_active=True, match__date_time__gte=now,
        ).select_related('match').order_by('match__date_time').first()
        variant = copy_variant(user, 'weekly_recap')
        title = 'Your week on Rivalink'
        parts = [f'{played} match{"es" if played != 1 else ""} played']
        if hosted:
            parts.append(f'{hosted} hosted')
        if streak['weeks']:
            parts.append(f'{streak["weeks"]}-week streak')
        message = ' · '.join(parts) + '.'
        if upcoming:
            message += f' Next up: "{upcoming.match.title}" {upcoming.match.date_time:%a %H:%M}.'
        else:
            message += ' Find your next game this week.'
        if variant == 'B':
            message = 'Your recap: ' + message
        if notify_once(
            user, title, message, dedupe_hours=24 * 6,
            kind='weekly_recap', variant=variant,
        ):
            sent += 1
    return sent
