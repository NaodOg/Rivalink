from datetime import timedelta

from django.conf import settings
from django.utils import timezone
from rest_framework.authentication import TokenAuthentication
from rest_framework.exceptions import AuthenticationFailed


class ExpiringTokenAuthentication(TokenAuthentication):
    """Token auth that rejects tokens older than `TOKEN_TTL_DAYS`.

    Set `TOKEN_TTL_DAYS=0` in the environment to disable expiry.
    """

    def authenticate_credentials(self, key):
        user, token = super().authenticate_credentials(key)
        ttl_days = getattr(settings, 'TOKEN_TTL_DAYS', 30)
        if ttl_days and token.created < timezone.now() - timedelta(days=ttl_days):
            token.delete()
            raise AuthenticationFailed('Session expired. Please log in again.')
        return user, token
