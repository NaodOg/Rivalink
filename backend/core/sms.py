"""SMS delivery.

Same pattern as push: works through a provider when configured, otherwise logs
so OTP flows can be tested in development without a gateway. Set SMS_API_KEY +
SMS_PROVIDER_URL to enable.
"""
import logging

import requests
from django.conf import settings

log = logging.getLogger(__name__)


def send_sms(phone, message):
    """Best-effort SMS. Returns True if handed to the provider, else False."""
    key = getattr(settings, 'SMS_API_KEY', '') or ''
    url = getattr(settings, 'SMS_PROVIDER_URL', '') or ''
    if not key or not url:
        log.warning('SMS (dev — not sent): to=%s msg=%s', phone, message)
        return False
    try:
        requests.post(url, json={'to': phone, 'message': message, 'api_key': key}, timeout=10)
        return True
    except requests.RequestException as e:
        log.warning('SMS send failed for %s: %s', phone, e)
        return False
