import logging

from .models import AuditLog

logger = logging.getLogger('rivalink.security')


def client_ip(request):
    xff = request.META.get('HTTP_X_FORWARDED_FOR')
    if xff:
        return xff.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR', '')


def log_event(request, action, user=None, status='ok', detail=''):
    """Best-effort audit trail + structured log line. Never raises."""
    try:
        AuditLog.objects.create(
            user=user if getattr(user, 'is_authenticated', False) else None,
            action=action,
            status=status,
            ip=client_ip(request)[:64],
            user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:255],
            detail=detail[:500],
        )
    except Exception:
        pass
    logger.info('audit action=%s status=%s user=%s ip=%s detail=%s',
                action, status, getattr(user, 'id', None), client_ip(request), detail)
