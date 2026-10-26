from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.conf import settings
from django.db import transaction
from django.utils import timezone
from datetime import datetime, timedelta, time
from decimal import Decimal
from .models import Match, Notification, Venue, VenueBooking, VenueRating
from .monetization import (
    venue_commission, record_transaction, BOOKING_SLOT_HOURS, money,
)
from .serializers import (
    err_msg as _err_msg, display_name,
    venue_to_dict as _venue_to_dict, venue_booking_to_dict as _venue_booking_to_dict,
)
from .validators import (
    SensitiveWriteThrottle, validate_string, validate_optional_string, validate_int, validate_decimal, sanitize_text,
    validate_image, validate_boolean,
)


from .analytics import track
from .view_shared import (
    _get_quick_available_slots,
)


@api_view(['POST'])
def create_venue(request):
    """
    Create a new venue
    """
    try:
        if request.user.is_anonymous:
            return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

        try:
            raw = request.data
            def _get(d, key, default=''):
                v = d.get(key, default)
                return v if v is not None else default
            name = validate_string(_get(raw, 'name'), 200, 'Venue name')
            description = sanitize_text(validate_optional_string(_get(raw, 'description'), 5000, 'Description'))
            address = validate_string(_get(raw, 'address'), 300, 'Address')
            city = validate_string(_get(raw, 'city'), 100, 'City')
            sports = validate_optional_string(_get(raw, 'sports'), 500, 'Sports')
            capacity = validate_int(_get(raw, 'capacity', '0'), 0, 100000, 'Capacity')
            price = validate_decimal(_get(raw, 'slot_price', '0'), 0, 99999, 'Price per 2-hour slot')
            amenities = validate_optional_string(_get(raw, 'amenities'), 2000, 'Amenities')
            opening_time = _get(raw, 'opening_time') or None
            closing_time = _get(raw, 'closing_time') or None
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        venue = Venue.objects.create(
            owner=request.user,
            name=name,
            description=description,
            address=address,
            city=city,
            sports=sports,
            slot_price=price,
            capacity=capacity,
            amenities=amenities,
            opening_time=opening_time,
            closing_time=closing_time,
        )

        uploaded = request.FILES.get('image')
        if uploaded:
            try:
                validate_image(uploaded)
            except ValueError as e:
                return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
            from django.core.files.storage import default_storage
            import uuid
            ext = uploaded.name.rsplit('.', 1)[-1] if '.' in uploaded.name else 'jpg'
            filename = f'venues/{uuid.uuid4().hex}.{ext}'
            saved = default_storage.save(filename, uploaded)
            url = f'{settings.MEDIA_URL}{saved}'
            venue.images = url
            venue.save(update_fields=['images'])

        return Response({
            'success': True,
            'venue': _venue_to_dict(venue)
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['GET'])
@permission_classes([AllowAny])
def list_venues(request):
    """
    List all venues, optionally filtered
    """
    try:
        sport = request.query_params.get('sport', '')
        city = request.query_params.get('city', '')
        available_only = request.query_params.get('available', 'true').lower() == 'true'
        
        queryset = Venue.objects.select_related('owner')
        
        if available_only:
            queryset = queryset.filter(is_available=True)
        
        if sport:
            queryset = queryset.filter(sports__icontains=sport)
        
        if city:
            queryset = queryset.filter(city__icontains=city)
        
        date_param = request.query_params.get('date')
        if date_param:
            try:
                target_date = datetime.fromisoformat(date_param).date()
            except Exception:
                target_date = timezone.localdate()
        else:
            target_date = timezone.localdate()

        from collections import defaultdict
        bookings_by_venue = defaultdict(list)
        for b in VenueBooking.objects.filter(
            venue_id__in=queryset.values_list('id', flat=True),
            date=target_date,
            status__in=['pending', 'confirmed'],
        ).values('venue_id', 'start_time', 'end_time'):
            bookings_by_venue[b['venue_id']].append(b)

        venues = []
        for venue in queryset:
            venue_data = _venue_to_dict(venue)
            venue_data['quick_available_slots'] = _get_quick_available_slots(
                venue, target_date, active_bookings=bookings_by_venue.get(venue.id, [])
            )
            venue_data['primary_image'] = venue.image_list[0] if venue.image_list else None
            venues.append(venue_data)
        
        return Response({
            'success': True,
            'venues': venues
        })
        
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['GET'])
@permission_classes([AllowAny])
def get_venue(request, venue_id):
    """
    Get venue details
    """
    try:
        venue = Venue.objects.get(id=venue_id)
        return Response({
            'success': True,
            'venue': _venue_to_dict(venue)
        })
    except Venue.DoesNotExist:
        return Response({'error': 'Venue not found'}, status=status.HTTP_404_NOT_FOUND)




@api_view(['GET'])
def get_my_venues(request):
    """
    Get venues owned by current user
    """
    try:
        venues = Venue.objects.filter(owner=request.user).select_related('owner')
        return Response({
            'success': True,
            'venues': [_venue_to_dict(v) for v in venues]
        })
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['PUT'])
def update_venue(request, venue_id):
    """
    Update venue details
    """
    try:
        venue = Venue.objects.get(id=venue_id, owner=request.user)
        
        try:
            if 'name' in request.data:
                venue.name = validate_string(request.data['name'], 100, 'Name')
            if 'description' in request.data:
                venue.description = sanitize_text(validate_optional_string(request.data['description'], 5000, 'Description'))
            if 'address' in request.data:
                venue.address = validate_optional_string(request.data['address'], 300, 'Address')
            if 'city' in request.data:
                venue.city = validate_optional_string(request.data['city'], 100, 'City')
            if 'sports' in request.data:
                venue.sports = validate_optional_string(request.data['sports'], 100, 'Sports')
            if 'slot_price' in request.data:
                venue.slot_price = validate_decimal(request.data['slot_price'], 0, 999999, 'Price per 2-hour slot')
            if 'capacity' in request.data:
                venue.capacity = validate_int(request.data['capacity'], 0, 100000, 'Capacity')
            if 'amenities' in request.data:
                venue.amenities = sanitize_text(validate_optional_string(request.data['amenities'], 2000, 'Amenities'))
            if 'is_available' in request.data:
                venue.is_available = validate_boolean(request.data['is_available'], 'Is available')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        venue.save()
        
        return Response({
            'success': True,
            'venue': _venue_to_dict(venue)
        })
        
    except Venue.DoesNotExist:
        return Response({'error': 'Venue not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['DELETE'])
@throttle_classes([SensitiveWriteThrottle])
def delete_venue(request, venue_id):
    try:
        venue = Venue.objects.get(id=venue_id, owner=request.user)
        venue.delete()
        return Response({'success': True, 'message': 'Venue deleted successfully'})
    except Venue.DoesNotExist:
        return Response({'error': 'Venue not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




def _parse_time(value):
    """Normalise a request time ('10:00') or a datetime.time to datetime.time."""
    if isinstance(value, time):
        return value
    return datetime.strptime(str(value), '%H:%M').time()


def _has_conflict(venue, date, start_time, end_time, exclude_booking_id=None):
    """True when an active booking already covers this slot."""
    start = _parse_time(start_time)
    end = _parse_time(end_time)

    qs = VenueBooking.objects.filter(
        venue=venue, date=date, status__in=['pending', 'confirmed'])
    if exclude_booking_id:
        qs = qs.exclude(id=exclude_booking_id)
    for b in qs:
        if start < b.end_time and end > b.start_time:
            return True
    return False


@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def book_venue(request):
    """
    Book a venue for a date/time
    """
    try:
        venue_id = request.data.get('venue_id')
        date = request.data.get('date')
        start_time = request.data.get('start_time')
        end_time = request.data.get('end_time')
        match_id = request.data.get('match_id')
        notes = sanitize_text(request.data.get('notes', ''))
        
        if not venue_id or not date or not start_time or not end_time:
            return Response({'error': 'venue_id, date, start_time, and end_time are required'}, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            notes = validate_optional_string(notes, 5000, 'Notes')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        venue = Venue.objects.get(id=venue_id)
        
        # Validate the date and compute hours; reject overnight/invalid ranges.
        try:
            booking_date = datetime.strptime(str(date), '%Y-%m-%d').date()
        except (ValueError, TypeError):
            return Response({'error': 'date must be in YYYY-MM-DD format'},
                            status=status.HTTP_400_BAD_REQUEST)
        
        # Calculate hours and price
        try:
            start_dt = datetime.strptime(start_time, '%H:%M')
            end_dt = datetime.strptime(end_time, '%H:%M')
        except (ValueError, TypeError):
            return Response({'error': 'start_time and end_time must be in HH:MM format'},
                            status=status.HTTP_400_BAD_REQUEST)
        
        hours = int((end_dt - start_dt).total_seconds() / 3600)
        if end_dt <= start_dt:
            return Response({'error': 'end_time must be after start_time'},
                            status=status.HTTP_400_BAD_REQUEST)

        if hours < BOOKING_SLOT_HOURS:
            return Response({
                'error': f'Venues are booked in {BOOKING_SLOT_HOURS}-hour slots '
                         f'(minimum {BOOKING_SLOT_HOURS} hours).',
            }, status=status.HTTP_400_BAD_REQUEST)

        match = None
        if match_id:
            match = Match.objects.filter(id=match_id).first()
            if match and match.organizer_id != request.user.id:
                return Response({'error': 'Only the match organizer can attach this match'},
                                status=status.HTTP_403_FORBIDDEN)

        # Guard against double-booking the same slot.
        with transaction.atomic():
            if _has_conflict(venue, booking_date, start_time, end_time):
                return Response({
                    'error': 'That slot is already booked. Pick another time.',
                }, status=status.HTTP_409_CONFLICT)

            slots = max(1, hours // BOOKING_SLOT_HOURS)
            total_price = money(Decimal(venue.slot_price) * slots)

            booking = VenueBooking.objects.create(
                venue=venue,
                booked_by=request.user,
                date=booking_date,
                start_time=start_time,
                end_time=end_time,
                hours=hours,
                total_price=total_price,
                notes=notes,
                match=match,
            )
        
        track(request.user, 'booking_created', {
            'venue_id': venue.id, 'price': float(total_price), 'hours': hours,
        })

        # Create notification for venue owner
        Notification.objects.create(
            user=venue.owner,
            notification_type='general',
            title='New Venue Booking',
            message=f'{request.user.first_name} booked {venue.name}',
        )

        commission = venue_commission(booking.total_price)
        record_transaction(
            'venue_commission', commission, payer=request.user,
            reference_type='venue_booking', reference_id=booking.id,
            note=f'Commission on {venue.name} booking ({booking.hours}h)',
        )

        return Response({
            'success': True,
            'booking': _venue_booking_to_dict(booking),
            'platform_commission': str(commission),
        }, status=status.HTTP_201_CREATED)
        
    except Venue.DoesNotExist:
        return Response({'error': 'Venue not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['GET'])
def get_venue_bookings(request):
    """
    Get bookings - as venue owner or as booker
    """
    try:
        as_owner = request.query_params.get('as', 'owner')
        venue_id = request.query_params.get('venue_id')
        status_filter = request.query_params.get('status')
        scope = request.query_params.get('scope')

        if as_owner == 'owner':
            venues = Venue.objects.filter(owner=request.user).select_related('owner')
            bookings = VenueBooking.objects.filter(venue__in=venues)
        else:
            bookings = VenueBooking.objects.filter(booked_by=request.user)

        if venue_id:
            bookings = bookings.filter(venue_id=venue_id)
        if status_filter:
            bookings = bookings.filter(status=status_filter)

        today = timezone.localdate()
        if scope == 'upcoming':
            bookings = bookings.filter(date__gte=today)
        elif scope == 'past':
            bookings = bookings.filter(date__lt=today)

        bookings = bookings.select_related('venue', 'match', 'booked_by').order_by('-date', '-start_time')

        return Response({
            'success': True,
            'bookings': [_venue_booking_to_dict(b) for b in bookings]
        })
        
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




def _apply_cancellation_policy(booking, request):
    """Charge the venue's late-cancellation fee when applicable."""
    venue = booking.venue
    window = venue.cancellation_hours or 0
    percent = venue.cancellation_fee_percent or 0
    if window <= 0 or percent <= 0:
        return money(0)

    booking_dt = timezone.make_aware(datetime.combine(booking.date, booking.start_time))
    hours = (booking_dt - timezone.now()).total_seconds() / 3600
    if hours >= window:
        return money(0)

    fee = money(Decimal(booking.total_price) * Decimal(percent) / Decimal(100))
    if fee > 0:
        record_transaction(
            'cancellation_fee', fee, payer=request.user,
            reference_type='venue_booking', reference_id=booking.id,
            note=f'Late cancellation (<{window}h) at {venue.name}',
        )
    return fee


@api_view(['POST'])
def update_venue_booking(request, booking_id):
    """
    Update booking status
    """
    try:
        new_status = request.data.get('status')
        valid_statuses = ['confirmed', 'cancelled']
        
        if new_status not in valid_statuses:
            return Response({'error': 'Invalid status'}, status=status.HTTP_400_BAD_REQUEST)
        
        booking = VenueBooking.objects.get(id=booking_id)
        
        is_owner = booking.venue.owner_id == request.user.id
        is_booker = booking.booked_by_id == request.user.id
        if not is_owner and not is_booker:
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        if new_status == booking.status:
            return Response({'success': True, 'booking': _venue_booking_to_dict(booking)})

        allowed_from = {
            'confirmed': ['pending'],
            'cancelled': ['pending', 'confirmed'],
        }
        if booking.status not in allowed_from[new_status]:
            return Response({'error': f'Cannot change a {booking.status} booking to {new_status}'},
                            status=status.HTTP_400_BAD_REQUEST)
        if new_status == 'confirmed' and not is_owner:
            return Response({'error': 'Only the venue owner can confirm bookings'},
                            status=status.HTTP_403_FORBIDDEN)

        cancellation_fee = None
        if new_status == 'cancelled':
            cancellation_fee = _apply_cancellation_policy(booking, request)
            if booking.payment_status == 'paid':
                booking.payment_status = 'refunded'
                record_transaction(
                    'venue_commission', money(booking.total_price),
                    payer=request.user, reference_type='venue_booking',
                    reference_id=booking.id, status='refunded',
                    note=f'Booking refunded at {booking.venue.name}',
                )

        booking.status = new_status
        booking.save()

        payload = {
            'success': True,
            'booking': _venue_booking_to_dict(booking),
        }
        if cancellation_fee is not None:
            payload['cancellation_fee'] = str(cancellation_fee)
        return Response(payload)        
    except VenueBooking.DoesNotExist:
        return Response({'error': 'Booking not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def rate_venue(request, venue_id):
    """
    Rate a venue
    """
    try:
        try:
            rating_value = int(request.data.get('rating'))
        except (TypeError, ValueError):
            return Response({'error': 'rating must be an integer between 1 and 5'},
                            status=status.HTTP_400_BAD_REQUEST)
        comment = sanitize_text(request.data.get('comment', ''))
        
        try:
            comment = validate_optional_string(comment, 5000, 'Comment')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        if rating_value < 1 or rating_value > 5:
            return Response({'error': 'Rating must be between 1 and 5'}, status=status.HTTP_400_BAD_REQUEST)
        
        venue = Venue.objects.get(id=venue_id)
        
        # You can only rate a venue you have actually booked.
        has_booking = VenueBooking.objects.filter(
            venue=venue, booked_by=request.user,
            status__in=['confirmed', 'completed'],
        ).exists()
        if not has_booking:
            return Response({'error': 'You can only rate a venue you have booked'},
                            status=status.HTTP_403_FORBIDDEN)
        
        rating, created = VenueRating.objects.get_or_create(
            venue=venue,
            rated_by=request.user,
            defaults={'rating': rating_value, 'comment': comment}
        )
        
        if not created:
            rating.rating = rating_value
            rating.comment = comment
            rating.save()
        
        # Update average rating
        ratings = VenueRating.objects.filter(venue=venue)
        avg = sum(r.rating for r in ratings) / len(ratings)
        venue.average_rating = round(avg, 2)
        venue.save()
        
        return Response({
            'success': True,
            'message': 'Rating submitted'
        })
        
    except Venue.DoesNotExist:
        return Response({'error': 'Venue not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Tournament System ──


# ── Venue owner: schedule + revenue ──────────────────────────────────────

def _schedule_for_day(venue, day, bookings):
    """Every 2-hour slot for a day, marked booked/free."""
    opening = venue.opening_time or time(8, 0)
    closing = venue.closing_time or time(22, 0)
    cursor = datetime.combine(day, opening)
    end_of_day = datetime.combine(day, closing)
    slots = []
    while cursor + timedelta(hours=BOOKING_SLOT_HOURS) <= end_of_day:
        slot_end = cursor + timedelta(hours=BOOKING_SLOT_HOURS)
        hit = None
        for b in bookings:
            b_start = datetime.combine(day, b.start_time)
            b_end = datetime.combine(day, b.end_time)
            if cursor < b_end and slot_end > b_start:
                hit = b
                break
        slots.append({
            'start': cursor.strftime('%H:%M'),
            'end': slot_end.strftime('%H:%M'),
            'status': 'booked' if hit else 'free',
            'booking': {
                'id': hit.id,
                'status': hit.status,
                'booked_by': display_name(hit.booked_by) if hit.booked_by else '',
                'match_id': hit.match_id,
                'match_title': hit.match.title if hit.match else None,
                'price': str(hit.total_price),
            } if hit else None,
        })
        cursor = slot_end
    return slots


@api_view(['GET'])
def venue_schedule(request, venue_id):
    """Day-by-day slot grid for a venue (owner only)."""
    try:
        venue = Venue.objects.get(id=venue_id)
    except Venue.DoesNotExist:
        return Response({'error': 'Venue not found'}, status=status.HTTP_404_NOT_FOUND)

    if venue.owner != request.user:
        return Response({'error': 'Only the venue owner can view the schedule'},
                        status=status.HTTP_403_FORBIDDEN)

    def parse_date(value, fallback):
        if not value:
            return fallback
        try:
            return datetime.strptime(value, '%Y-%m-%d').date()
        except (ValueError, TypeError):
            return fallback

    today = timezone.localdate()
    from_date = parse_date(request.query_params.get('from'), today)
    to_date = parse_date(request.query_params.get('to'), from_date + timedelta(days=6))
    if to_date < from_date:
        from_date, to_date = to_date, from_date
    if (to_date - from_date).days > 60:
        to_date = from_date + timedelta(days=60)

    bookings = list(VenueBooking.objects.filter(
        venue=venue, date__gte=from_date, date__lte=to_date,
        status__in=['pending', 'confirmed', 'completed'],
    ).select_related('booked_by', 'match'))

    days = []
    day = from_date
    while day <= to_date:
        day_bookings = [b for b in bookings if b.date == day]
        slots = _schedule_for_day(venue, day, day_bookings)
        booked = sum(1 for s in slots if s['status'] == 'booked')
        days.append({
            'date': day.isoformat(),
            'weekday': day.strftime('%a'),
            'slots': slots,
            'booked': booked,
            'free': len(slots) - booked,
            'revenue': str(money(sum(
                b.total_price for b in day_bookings if b.status in ('confirmed', 'completed')))),
        })
        day += timedelta(days=1)

    return Response({
        'success': True,
        'venue': {
            'id': venue.id, 'name': venue.name,
            'slot_price': str(venue.slot_price),
            'opening': (venue.opening_time or time(8, 0)).strftime('%H:%M'),
            'closing': (venue.closing_time or time(22, 0)).strftime('%H:%M'),
        },
        'from': from_date.isoformat(),
        'to': to_date.isoformat(),
        'days': days,
    })


@api_view(['GET'])
def venue_revenue(request):
    """Revenue breakdown for the owner: per venue + per month."""
    venues = list(Venue.objects.filter(owner=request.user))
    if not venues:
        return Response({'success': True, 'total_collected': '0.00', 'total_pending': '0.00',
                         'by_venue': [], 'by_month': []})

    bookings = list(VenueBooking.objects.filter(venue__in=venues).select_related('venue'))

    def bucket(items):
        collected = money(sum(b.total_price for b in items if b.status in ('confirmed', 'completed')))
        pending = money(sum(b.total_price for b in items if b.status == 'pending'))
        return collected, pending

    by_venue = []
    for v in venues:
        vq = [b for b in bookings if b.venue_id == v.id]
        collected, pending = bucket(vq)
        by_venue.append({
            'venue_id': v.id, 'name': v.name, 'city': v.city,
            'bookings': len(vq), 'collected': str(collected), 'pending': str(pending),
            'verification_status': v.verification_status,
            'average_rating': str(v.average_rating),
        })

    months = {}
    for b in bookings:
        months.setdefault(b.date.strftime('%Y-%m'), []).append(b)
    by_month = []
    for key in sorted(months.keys(), reverse=True)[:12]:
        collected, pending = bucket(months[key])
        by_month.append({'month': key, 'bookings': len(months[key]),
                         'collected': str(collected), 'pending': str(pending)})

    all_collected, all_pending = bucket(bookings)
    return Response({
        'success': True,
        'total_collected': str(all_collected),
        'total_pending': str(all_pending),
        'by_venue': by_venue,
        'by_month': by_month,
    })


@api_view(['GET'])
@permission_classes([AllowAny])
def venue_availability(request, venue_id):
    """Public availability for a venue.

    ?date=YYYY-MM-DD            -> single day
    ?from=YYYY-MM-DD&to=...     -> range (week strip)
    """
    try:
        venue = Venue.objects.get(id=venue_id, is_active=True)
    except Venue.DoesNotExist:
        return Response({'error': 'Venue not found'}, status=status.HTTP_404_NOT_FOUND)

    def parse_date(value, fallback):
        if not value:
            return fallback
        try:
            return datetime.strptime(value, '%Y-%m-%d').date()
        except (ValueError, TypeError):
            return fallback

    today = timezone.localdate()
    from_str = request.query_params.get('from')
    to_str = request.query_params.get('to')

    if from_str or to_str:
        from_date = parse_date(from_str, today)
        to_date = parse_date(to_str, from_date + timedelta(days=6))
        if to_date < from_date:
            from_date, to_date = to_date, from_date
        if (to_date - from_date).days > 30:
            to_date = from_date + timedelta(days=30)

        bookings = list(VenueBooking.objects.filter(
            venue=venue, date__gte=from_date, date__lte=to_date,
            status__in=['pending', 'confirmed']))

        days = []
        day = from_date
        while day <= to_date:
            day_bookings = [b for b in bookings if b.date == day]
            slots = [{'start': s['start'], 'end': s['end'], 'status': s['status']}
                     for s in _schedule_for_day(venue, day, day_bookings)]
            days.append({
                'date': day.isoformat(),
                'weekday': day.strftime('%a'),
                'slots': slots,
                'free': sum(1 for s in slots if s['status'] == 'free'),
                'booked': sum(1 for s in slots if s['status'] == 'booked'),
            })
            day += timedelta(days=1)

        return Response({
            'success': True,
            'venue': {'id': venue.id, 'name': venue.name, 'slot_price': str(venue.slot_price)},
            'from': from_date.isoformat(),
            'to': to_date.isoformat(),
            'days': days,
        })

    target = parse_date(request.query_params.get('date'), today)
    bookings = list(VenueBooking.objects.filter(
        venue=venue, date=target, status__in=['pending', 'confirmed']))
    slots = [{'start': s['start'], 'end': s['end'], 'status': s['status']}
             for s in _schedule_for_day(venue, target, bookings)]

    return Response({
        'success': True,
        'venue': {'id': venue.id, 'name': venue.name, 'slot_price': str(venue.slot_price)},
        'date': target.isoformat(),
        'slots': slots,
        'free': sum(1 for s in slots if s['status'] == 'free'),
        'booked': sum(1 for s in slots if s['status'] == 'booked'),
    })
