"""Push notification delivery.

Sends to every active device a user has registered. When FCM is not yet
configured (no FCM_SERVER_KEY) it logs instead of failing, so the rest of the
system — in-app notifications, reminders — keeps working until you drop in your
Firebase server key.
"""
import json
import logging

import requests
from django.conf import settings

from .models import DeviceToken, Notification

log = logging.getLogger(__name__)


def _fcm_server_key():
    return getattr(settings, 'FCM_SERVER_KEY', '') or ''


def send_push(user, title, body, data=None):
    """Best-effort push to all of a user's devices. Returns number sent."""
    tokens = list(
        DeviceToken.objects.filter(user=user, is_active=True).values_list('token', flat=True)
    )
    if not tokens:
        return 0

    key = _fcm_server_key()
    if not key:
        log.info('FCM not configured — would push "%s" to %d device(s) for %s',
                 title, len(tokens), user.username)
        return 0

    sent = 0
    for token in tokens:
        try:
            resp = requests.post(
                'https://fcm.googleapis.com/fcm/send',
                headers={
                    'Authorization': f'key={key}',
                    'Content-Type': 'application/json',
                },
                data=json.dumps({
                    'to': token,
                    'notification': {'title': title, 'body': body},
                    'data': data or {},
                }),
                timeout=10,
            )
            if resp.status_code == 200:
                sent += 1
            else:
                log.warning('FCM non-200 (%s) for %s', resp.status_code, user.username)
        except requests.RequestException as e:
            log.warning('Push failed for %s: %s', user.username, e)
    return sent


def notify(user, notification_type, title, message, match=None, team=None):
    """Create the in-app Notification *and* fire a push. Use this everywhere."""
    notification = Notification.objects.create(
        user=user,
        notification_type=notification_type,
        title=title,
        message=message,
        related_match=match,
        related_team=team,
    )
    send_push(user, title, message, {'type': notification_type})
    return notification


def push_many(users, title, body, data=None):
    """Fire a push to each user (no in-app Notification created)."""
    sent = 0
    for user in users:
        sent += send_push(user, title, body, data)
    return sent
