import uuid
import hmac
import hashlib
from decimal import Decimal
import requests as http_requests
from django.conf import settings
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework import status
from django.utils import timezone
from datetime import timedelta
from .models import UserProfile, Payment, MatchParticipant, VenueBooking
from .monetization import PREMIUM_PRICE_ETB as PREMIUM_AMOUNT, record_transaction
from .audit import log_event
from .escrow import hold
from .analytics import track

CHAPA_API_URL = "https://api.chapa.co/v1/transaction/initialize"
CHAPA_VERIFY_URL = "https://api.chapa.co/v1/transaction/verify/"


def _get_chapa_key():
    return getattr(settings, 'CHAPA_SECRET_KEY', None) or ''


def _get_webhook_secret():
    return getattr(settings, 'CHAPA_WEBHOOK_SECRET', None) or _get_chapa_key()


def _verify_chapa_signature(request):
    """Verify the Chapa webhook HMAC-SHA256 signature.

    Returns True/False when a secret is configured, None when no secret is
    configured (verification impossible). Headers are checked case-insensitively
    for both `x-chapa-signature` and `chapa-signature`.
    """
    secret = _get_webhook_secret()
    if not secret:
        return None

    signature = request.headers.get('X-Chapa-Signature') or request.headers.get('Chapa-Signature')
    if not signature:
        return False

    expected = hmac.new(
        secret.encode('utf-8'), request.body, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature.strip().lower())


def _settle_successful_payment(request, payment, tx_ref):
    """Apply a confirmed payment to whatever it was for."""
    if payment.payment_type == 'match_share':
        participant = MatchParticipant.objects.filter(
            match_id=payment.reference_id, user=payment.user).first()
        if participant:
            hold(participant, amount=payment.amount)
            if participant.user_id == participant.match.organizer_id and \
                    participant.match.venue_id and \
                    participant.match.booking_status != 'confirmed':
                from .reservations import reserve_for_match
                from .escrow import refund_participant
                try:
                    reserve_for_match(participant.match)
                except ValueError:
                    refund_participant(
                        participant, percent=100,
                        reason='Venue slot was taken before payment settled')
                    from .push import notify
                    notify(
                        participant.user, 'general', 'Venue slot unavailable',
                        f'The slot for "{participant.match.title}" was taken. '
                        'Your share was refunded. Pick another time.',
                        match=participant.match,
                    )
        log_event(request, 'payment_webhook', payment.user, 'ok',
                  f'match share held tx={tx_ref}')
        return

    if payment.payment_type == 'venue_booking':
        booking = VenueBooking.objects.filter(id=payment.reference_id).first()
        if booking and booking.payment_status != 'paid':
            booking.payment_status = 'paid'
            booking.paid_at = timezone.now()
            booking.save(update_fields=['payment_status', 'paid_at'])
            if booking.status == 'pending':
                booking.status = 'confirmed'
                booking.save(update_fields=['status'])
            booking.venue.total_bookings += 1
            booking.venue.save(update_fields=['total_bookings'])
            track(booking.booked_by, 'booking_paid', {
                'booking_id': booking.id, 'amount': str(booking.total_price),
            })
        log_event(request, 'payment_webhook', payment.user, 'ok',
                  f'venue booking paid tx={tx_ref}')
        return

    # default: premium subscription
    profile = UserProfile.get_or_create_for_user(payment.user)
    profile.is_premium = True
    profile.premium_expires = timezone.now() + timedelta(days=30)
    profile.save()

    track(payment.user, 'premium_purchased', {'amount': str(PREMIUM_AMOUNT)})

    record_transaction(
        'premium', PREMIUM_AMOUNT, payer=payment.user,
        reference_type='payment', reference_id=payment.id,
        status='collected', note='Premium subscription (1 month)',
    )
    log_event(request, 'payment_webhook', payment.user, 'ok', f'premium activated tx={tx_ref}')


@api_view(['POST'])
def initialize_premium_payment(request):
    user = request.user
    if not user.is_authenticated:
        return Response({'success': False, 'message': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    profile = UserProfile.get_or_create_for_user(user)

    if profile.premium_active:
        return Response({'success': False, 'message': 'You already have an active premium subscription'}, status=status.HTTP_400_BAD_REQUEST)

    chapa_secret = _get_chapa_key()
    if not chapa_secret:
        return Response({'success': False, 'message': 'Payment system not configured'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    tx_ref = f"RIVALINK-{uuid.uuid4().hex[:12].upper()}"

    email = user.email
    if not email:
        return Response({'success': False, 'message': 'Email required for payment. Please update your profile.'}, status=status.HTTP_400_BAD_REQUEST)

    payment = Payment.objects.create(
        user=user,
        tx_ref=tx_ref,
        amount=PREMIUM_AMOUNT,
        currency='ETB',
        payment_type='premium',
        description='Rivalink Premium Subscription - 1 month',
    )

    return_url = request.data.get('return_url', '')

    payload = {
        "amount": str(PREMIUM_AMOUNT),
        "currency": "ETB",
        "email": email,
        "tx_ref": tx_ref,
        "callback_url": f"{settings.SITE_URL}/api/payments/webhook/",
        "return_url": return_url,
        "customization": {
            "title": "Rivalink Premium",
            "description": "Premium Subscription - 100 ETB/month",
        }
    }

    headers = {
        "Authorization": f"Bearer {chapa_secret}",
        "Content-Type": "application/json",
    }

    try:
        resp = http_requests.post(CHAPA_API_URL, json=payload, headers=headers, timeout=30)
        data = resp.json()

        if resp.status_code == 200 and data.get('status') == 'success':
            checkout_url = data.get('data', {}).get('checkout_url', '')
            payment.chapa_tx_id = data.get('data', {}).get('tx_ref', tx_ref)
            payment.save()
            return Response({
                'success': True,
                'checkout_url': checkout_url,
                'tx_ref': tx_ref,
            })
        else:
            payment.status = 'failed'
            payment.save()
            error_msg = data.get('message', 'Payment initialization failed')
            return Response({'success': False, 'message': error_msg}, status=status.HTTP_400_BAD_REQUEST)

    except http_requests.RequestException:
        payment.status = 'failed'
        payment.save()
        return Response({'success': False, 'message': 'Payment service is temporarily unavailable. Please try again.'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)


@api_view(['POST'])
@permission_classes([])
def payment_webhook(request):
    signature_valid = _verify_chapa_signature(request)
    if signature_valid is False:
        log_event(request, 'payment_webhook', None, 'invalid_signature')
        return Response({'status': 'invalid_signature'}, status=status.HTTP_401_UNAUTHORIZED)

    tx_ref = request.data.get('tx_ref') or request.data.get('transaction_id', '')
    if not tx_ref:
        return Response({'status': 'error', 'message': 'Missing tx_ref'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        payment = Payment.objects.get(tx_ref=tx_ref)
    except Payment.DoesNotExist:
        return Response({'status': 'error', 'message': 'Payment not found'}, status=status.HTTP_404_NOT_FOUND)

    if payment.status == 'success':
        return Response({'status': 'already_processed'})

    # Authoritative confirmation comes from Chapa's server, not the webhook body.
    chapa_secret = _get_chapa_key()
    verified_status = ''
    chapa_tx_id = ''
    verify_error = None

    if chapa_secret:
        try:
            verify_resp = http_requests.get(
                f"{CHAPA_VERIFY_URL}{tx_ref}",
                headers={"Authorization": f"Bearer {chapa_secret}"},
                timeout=30,
            )
            verify_data = verify_resp.json()
            if verify_data.get('status') == 'success':
                verified_status = verify_data.get('data', {}).get('status', '')
                chapa_tx_id = verify_data.get('data', {}).get('id', '')
        except http_requests.RequestException as e:
            verify_error = str(e)

    body_status = request.data.get('status', '')

    if verified_status in ('success', 'completed'):
        payment.status = 'success'
        if chapa_tx_id:
            payment.chapa_tx_id = chapa_tx_id
        payment.save()

        _settle_successful_payment(request, payment, tx_ref)
        return Response({'status': 'success', 'message': 'Payment confirmed'})

    # Chapa's verification API is down: only accept the body when its HMAC
    # signature was verified with our secret. Never trust an unsigned body.
    if verify_error is not None and signature_valid is True and body_status in ('success', 'completed'):
        payment.status = 'success'
        payment.save()

        _settle_successful_payment(request, payment, tx_ref)
        return Response({'status': 'success', 'message': 'Payment confirmed'})

    payment.status = 'failed'
    payment.save()
    log_event(request, 'payment_webhook', payment.user, 'failed', tx_ref)
    return Response({'status': 'failed', 'message': 'Payment not successful'})


@api_view(['POST'])
def initialize_venue_booking_payment(request):
    """Start a Chapa checkout for a pending venue booking."""
    user = request.user
    if not user.is_authenticated:
        return Response({'success': False, 'message': 'Authentication required'},
                        status=status.HTTP_401_UNAUTHORIZED)

    booking_id = request.data.get('booking_id')
    try:
        booking_id = int(booking_id)
    except (TypeError, ValueError):
        return Response({'success': False, 'message': 'booking_id is required'},
                        status=status.HTTP_400_BAD_REQUEST)

    booking = VenueBooking.objects.filter(id=booking_id, booked_by=user).first()
    if not booking:
        return Response({'success': False, 'message': 'Booking not found'},
                        status=status.HTTP_404_NOT_FOUND)
    if booking.payment_status == 'paid':
        return Response({'success': True, 'already_paid': True})
    if booking.status == 'cancelled':
        return Response({'success': False, 'message': 'This booking was cancelled'},
                        status=status.HTTP_400_BAD_REQUEST)
    if booking.total_price <= 0:
        booking.payment_status = 'paid'
        booking.paid_at = timezone.now()
        booking.save(update_fields=['payment_status', 'paid_at'])
        return Response({'success': True, 'free': True})

    tx_ref = f"RIVALINK-VB{booking.id}-{uuid.uuid4().hex[:8].upper()}"
    payment = Payment.objects.create(
        user=user,
        tx_ref=tx_ref,
        amount=booking.total_price,
        currency='ETB',
        payment_type='venue_booking',
        reference_type='venue_booking',
        reference_id=booking.id,
        description=f'{booking.venue.name} — {booking.date} {booking.start_time}-{booking.end_time}',
    )

    chapa_secret = _get_chapa_key()
    if not chapa_secret:
        if settings.DEBUG:
            payment.status = 'success'
            payment.save(update_fields=['status'])
            booking.payment_status = 'paid'
            booking.paid_at = timezone.now()
            if booking.status == 'pending':
                booking.status = 'confirmed'
            booking.save(update_fields=['payment_status', 'paid_at', 'status'])
            record_transaction(
                'venue_commission', booking.total_price * Decimal('0.10'),
                payer=user, reference_type='venue_booking', reference_id=booking.id,
                status='collected',
                note=f'Commission on {booking.venue.name} booking (mock)',
            )
            return Response({'success': True, 'mock': True, 'tx_ref': tx_ref,
                             'payment_status': 'paid'})
        payment.status = 'failed'
        payment.save(update_fields=['status'])
        return Response({'success': False, 'message': 'Payment system not configured'},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    email = user.email
    if not email:
        return Response({'success': False,
                         'message': 'Email required for payment. Please update your profile.'},
                        status=status.HTTP_400_BAD_REQUEST)

    payload = {
        'amount': str(booking.total_price),
        'currency': 'ETB',
        'email': email,
        'tx_ref': tx_ref,
        'callback_url': f'{settings.SITE_URL}/api/payments/webhook/',
        'return_url': request.data.get('return_url', ''),
        'customization': {
            'title': booking.venue.name,
            'description': f'{booking.date} · {booking.start_time}-{booking.end_time}',
        },
    }
    try:
        resp = http_requests.post(
            CHAPA_API_URL, json=payload,
            headers={'Authorization': f'Bearer {chapa_secret}',
                     'Content-Type': 'application/json'},
            timeout=30,
        )
        data = resp.json()
        if resp.status_code == 200 and data.get('status') == 'success':
            payment.chapa_tx_id = data.get('data', {}).get('tx_ref', tx_ref)
            payment.save(update_fields=['chapa_tx_id'])
            return Response({
                'success': True,
                'checkout_url': data.get('data', {}).get('checkout_url', ''),
                'tx_ref': tx_ref,
            })
        payment.status = 'failed'
        payment.save(update_fields=['status'])
        return Response({'success': False,
                         'message': data.get('message', 'Payment initialization failed')},
                        status=status.HTTP_400_BAD_REQUEST)
    except http_requests.RequestException:
        payment.status = 'failed'
        payment.save(update_fields=['status'])
        return Response({'success': False,
                         'message': 'Payment service is temporarily unavailable.'},
                        status=status.HTTP_503_SERVICE_UNAVAILABLE)


@api_view(['GET'])
def payment_status(request):
    user = request.user
    if not user.is_authenticated:
        return Response({'success': False, 'message': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    profile = UserProfile.get_or_create_for_user(user)
    return Response({
        'success': True,
        'is_premium': profile.premium_active,
        'premium_expires': profile.premium_expires.isoformat() if profile.premium_expires else None,
    })


@api_view(['GET'])
def get_my_payments(request):
    user = request.user
    if not user.is_authenticated:
        return Response({'success': False, 'message': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    payments = Payment.objects.filter(user=user).order_by('-created_at')[:10]
    return Response({
        'success': True,
        'payments': [{
            'tx_ref': p.tx_ref,
            'amount': str(p.amount),
            'currency': p.currency,
            'payment_type': p.payment_type,
            'status': p.status,
            'created_at': p.created_at.isoformat(),
        } for p in payments]
    })
