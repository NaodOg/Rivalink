"""Notification bandits and send discipline.

Thompson sampling picks the best notification arm per user. Two experiments:
send-time window and copy variant. Frequency caps and quiet hours are enforced
outside the bandit so no optimization can spam a user.
"""
import random
from datetime import timedelta

from django.utils import timezone

from .experiments import variant_for
from .models import AnalyticsEvent, Notification, NotificationBandit

SEND_TIME_EXPERIMENT = 'send_time'
SEND_ARMS = ('morning', 'afternoon', 'evening')
QUIET_START = 22
QUIET_END = 7
MAX_PER_DAY = 2
MAX_PER_WEEK = 6
BANDIT_MIN_TRIALS = 4


def local_now(now=None):
    return timezone.localtime(now or timezone.now())


def send_window(now=None):
    hour = local_now(now).hour
    if 7 <= hour < 12:
        return 'morning'
    if 12 <= hour < 17:
        return 'afternoon'
    return 'evening'


def is_quiet_hours(now=None):
    hour = local_now(now).hour
    return hour >= QUIET_START or hour < QUIET_END


def choose_arm(user, experiment, arms):
    """Thompson sampling with a Beta(1, 1) prior for unseen arms."""
    rows = {
        row.arm: row for row in NotificationBandit.objects.filter(
            user=user, experiment=experiment, arm__in=arms)
    }
    best_arm = arms[0]
    best_draw = -1.0
    for arm in arms:
        row = rows.get(arm)
        alpha = row.alpha if row else 1
        beta = row.beta if row else 1
        draw = random.betavariate(max(1, alpha), max(1, beta))
        if draw > best_draw:
            best_draw = draw
            best_arm = arm
    return best_arm


def record_reward(user, experiment, arm, rewarded=True):
    if not arm:
        return None
    row, _ = NotificationBandit.objects.get_or_create(
        user=user, experiment=experiment, arm=arm)
    if rewarded:
        row.alpha += 1
    else:
        row.beta += 1
    row.save(update_fields=['alpha', 'beta', 'updated_at'])
    return row


def _trials(user, experiment):
    rows = NotificationBandit.objects.filter(user=user, experiment=experiment)
    return sum(max(0, row.alpha + row.beta - 2) for row in rows)


def copy_variant(user, kind='engagement'):
    experiment = f'notification_copy:{kind}'
    if _trials(user, experiment) >= BANDIT_MIN_TRIALS:
        return choose_arm(user, experiment, ('A', 'B'))
    return variant_for(user, experiment)


def pick(variant, control, treatment):
    return treatment if variant == 'B' else control


def _activity_windows(user, now, days=28):
    bands = {'morning': 0, 'afternoon': 0, 'evening': 0}
    rows = AnalyticsEvent.objects.filter(
        user=user, created_at__gte=now - timedelta(days=days),
    ).values_list('created_at', flat=True)
    for created_at in rows:
        bands[send_window(created_at)] += 1
    return bands


def send_time_allows(user, now=None):
    """True when this is a reasonable moment to nudge this user."""
    now = now or timezone.now()
    if is_quiet_hours(now):
        return False

    bands = _activity_windows(user, now)
    total = sum(bands.values())
    if total >= 8:
        top_two = sorted(bands, key=bands.get, reverse=True)[:2]
        if send_window(now) not in top_two:
            return False

    if _trials(user, SEND_TIME_EXPERIMENT) >= BANDIT_MIN_TRIALS:
        chosen = choose_arm(user, SEND_TIME_EXPERIMENT, SEND_ARMS)
        if chosen != send_window(now):
            return False
    return True


def notification_allowed(user, now=None, critical=False):
    if critical:
        return True
    now = now or timezone.now()
    day_count = Notification.objects.filter(
        user=user, created_at__gte=now - timedelta(hours=24)).count()
    if day_count >= MAX_PER_DAY:
        return False
    week_count = Notification.objects.filter(
        user=user, created_at__gte=now - timedelta(days=7)).count()
    return week_count < MAX_PER_WEEK


def record_notification_sent(user, kind, variant='', arm=''):
    from .analytics import track
    track(user, 'notification_sent', {
        'kind': kind or 'engagement',
        'variant': variant,
        'arm': arm or send_window(),
    })


def update_bandits(days=7, reward_window_hours=24, now=None):
    """Reward each notification arm by whether the user returned within 24h."""
    now = now or timezone.now()
    window_start = now - timedelta(days=days)
    settled_before = now - timedelta(hours=reward_window_hours)
    events = AnalyticsEvent.objects.filter(
        name='notification_sent',
        created_at__gte=window_start,
        created_at__lte=settled_before,
    ).order_by('created_at')[:2000]

    updated = 0
    for event in events:
        props = dict(event.properties or {})
        if props.get('rewarded'):
            continue
        rewarded = AnalyticsEvent.objects.filter(
            user=event.user,
            created_at__gt=event.created_at,
            created_at__lte=event.created_at + timedelta(hours=reward_window_hours),
        ).exclude(name='notification_sent').exists()

        variant = props.get('variant', '')
        arm = props.get('arm', '')
        kind = props.get('kind', 'engagement')
        if variant:
            record_reward(event.user, f'notification_copy:{kind}', variant, rewarded)
        if arm:
            record_reward(event.user, SEND_TIME_EXPERIMENT, arm, rewarded)

        props['rewarded'] = True
        props['reward'] = rewarded
        event.properties = props
        event.save(update_fields=['properties'])
        updated += 1
    return updated
