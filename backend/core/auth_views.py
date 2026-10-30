import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .audit import log_event
from .models import UserProfile
from .serializers import err_msg as _err_msg
from .sms import send_sms
from .validators import AuthRateThrottle, validate_email, validate_password

RESET_CODE_TTL_MINUTES = 30


@api_view(['POST'])
def change_password(request):
    """Change the password and rotate the auth token (signs out other devices)."""
    current = request.data.get('current_password') or ''
    new = request.data.get('new_password') or ''

    if not request.user.check_password(current):
        log_event(request, 'password_change', request.user, 'failed', 'wrong current password')
        return Response({'error': 'Current password is incorrect'},
                        status=status.HTTP_400_BAD_REQUEST)

    try:
        validate_password(new)
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

    request.user.set_password(new)
    request.user.save()

    Token.objects.filter(user=request.user).delete()
    token = Token.objects.create(user=request.user)

    log_event(request, 'password_change', request.user, 'ok', 'token rotated')
    return Response({
        'success': True,
        'token': token.key,
        'message': 'Password updated. All other sessions were signed out.',
    })


@api_view(['POST'])
def logout_all(request):
    """Invalidate the user's token — signs out every device."""
    Token.objects.filter(user=request.user).delete()
    log_event(request, 'logout_all', request.user, 'ok')
    return Response({'success': True, 'message': 'Signed out of all devices'})


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def password_reset_request(request):
    """Start a password reset. Always returns the same response (no enumeration)."""
    try:
        email = validate_email(request.data.get('email'))
    except ValueError:
        return Response({'success': True,
                         'message': 'If that account exists, a reset code was sent.'})

    payload = {'success': True, 'message': 'If that account exists, a reset code was sent.'}
    user = User.objects.filter(username=email).first()
    if user:
        profile = UserProfile.get_or_create_for_user(user)
        code = f'{secrets.randbelow(1000000):06d}'
        profile.reset_token = code
        profile.reset_token_expires = timezone.now() + timedelta(minutes=RESET_CODE_TTL_MINUTES)
        profile.save(update_fields=['reset_token', 'reset_token_expires'])
        sent = send_sms(profile.phone, f'Your Victiqo password reset code is {code}') if profile.phone else False
        log_event(request, 'password_reset_request', user, 'ok', f'sms_sent={sent}')
        if not sent and settings.DEBUG:
            payload['dev_code'] = code
    else:
        log_event(request, 'password_reset_request', None, 'unknown_email', email)

    return Response(payload)


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def password_reset_confirm(request):
    """Finish a password reset with the emailed/SMS code."""
    try:
        email = validate_email(request.data.get('email'))
        code = (request.data.get('code') or '').strip()
        new_password = validate_password(request.data.get('new_password'))
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

    user = User.objects.filter(username=email).first()
    if not user:
        return Response({'error': 'Invalid or expired code'}, status=status.HTTP_400_BAD_REQUEST)

    profile = UserProfile.get_or_create_for_user(user)
    valid = (
        bool(profile.reset_token)
        and secrets.compare_digest(profile.reset_token, code)
        and profile.reset_token_expires is not None
        and profile.reset_token_expires >= timezone.now()
    )
    if not valid:
        log_event(request, 'password_reset_confirm', user, 'failed', 'invalid or expired code')
        return Response({'error': 'Invalid or expired code'}, status=status.HTTP_400_BAD_REQUEST)

    user.set_password(new_password)
    user.save()
    profile.reset_token = ''
    profile.reset_token_expires = None
    profile.save(update_fields=['reset_token', 'reset_token_expires'])
    Token.objects.filter(user=user).delete()

    log_event(request, 'password_reset_confirm', user, 'ok', 'all sessions signed out')
    return Response({'success': True, 'message': 'Password reset. Please log in.'})
