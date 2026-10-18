from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.conf import settings
from django.utils import timezone
from datetime import datetime
from .models import Match, Notification, Venue, VenueBooking, VenueRating
from .monetization import (
    venue_commission, record_transaction, BOOKING_SLOT_HOURS,
)
from .serializers import (
    err_msg as _err_msg, venue_to_dict as _venue_to_dict, venue_booking_to_dict as _venue_booking_to_dict,
)
from .validators import (
    SensitiveWriteThrottle, validate_string, validate_optional_string, validate_int, validate_decimal, sanitize_text,
    validate_image, validate_boolean,
)


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
        
        # Calculate hours and price
        try:
            start_dt = datetime.strptime(start_time, '%H:%M')
            end_dt = datetime.strptime(end_time, '%H:%M')
            hours = int((end_dt - start_dt).seconds / 3600)
        except (ValueError, TypeError):
            hours = 0

        if hours < BOOKING_SLOT_HOURS:
            return Response({
                'error': f'Venues are booked in {BOOKING_SLOT_HOURS}-hour slots '
                         f'(minimum {BOOKING_SLOT_HOURS} hours).',
            }, status=status.HTTP_400_BAD_REQUEST)

        slots = max(1, hours // BOOKING_SLOT_HOURS)
        total_price = float(venue.slot_price) * slots
        
        booking = VenueBooking.objects.create(
            venue=venue,
            booked_by=request.user,
            date=date,
            start_time=start_time,
            end_time=end_time,
            hours=hours,
            total_price=total_price,
            notes=notes
        )
        
        if match_id:
            try:
                booking.match = Match.objects.get(id=match_id)
                booking.save()
            except Match.DoesNotExist:
                pass
        
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
        
        if as_owner == 'owner':
            venues = Venue.objects.filter(owner=request.user).select_related('owner')
            bookings = VenueBooking.objects.filter(venue__in=venues).select_related('venue', 'match', 'booked_by')
        else:
            bookings = VenueBooking.objects.filter(booked_by=request.user).select_related('venue', 'match', 'booked_by')
        
        return Response({
            'success': True,
            'bookings': [_venue_booking_to_dict(b) for b in bookings]
        })
        
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




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
        
        if booking.venue.owner != request.user and booking.booked_by != request.user:
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        
        booking.status = new_status
        booking.save()
        
        return Response({
            'success': True,
            'booking': _venue_booking_to_dict(booking)
        })
        
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
        rating_value = int(request.data.get('rating'))
        comment = sanitize_text(request.data.get('comment', ''))
        
        try:
            comment = validate_optional_string(comment, 5000, 'Comment')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        if rating_value < 1 or rating_value > 5:
            return Response({'error': 'Rating must be between 1 and 5'}, status=status.HTTP_400_BAD_REQUEST)
        
        venue = Venue.objects.get(id=venue_id)
        
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
