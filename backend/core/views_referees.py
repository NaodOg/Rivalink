from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.contrib.auth.models import User
from .models import Match, Notification, Referee, RefereeBooking, RefereeRating
from .monetization import (
    referee_commission, record_transaction,
)
from .serializers import (
    err_msg as _err_msg, referee_to_dict as _referee_to_dict, booking_to_dict as _booking_to_dict,
)
from .validators import (
    validate_optional_string, validate_optional_int, validate_decimal, sanitize_text, validate_boolean,
)




@api_view(['POST'])
def create_referee_profile(request):
    """
    Create or update referee profile for the authenticated user
    """
    try:
        user = request.user
        
        try:
            sports = validate_optional_string(request.data.get('sports', ''), 500, 'Sports')
            experience_years = validate_optional_int(request.data.get('experience_years', 0), 0, 100, 'Experience years') or 0
            certification = validate_optional_string(request.data.get('certification', ''), 500, 'Certification')
            bio = sanitize_text(validate_optional_string(request.data.get('bio', ''), 1000, 'Bio'))
            hourly_rate = validate_decimal(request.data.get('hourly_rate', 0), 0, 99999, 'Hourly rate')
            referee_location = validate_optional_string(request.data.get('location', ''), 200, 'Location')
            is_available = validate_boolean(request.data.get('is_available', True), 'is_available')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        referee, created = Referee.objects.get_or_create(user=user)
        referee.sports = sports
        referee.experience_years = experience_years
        referee.certification = certification
        referee.bio = bio
        referee.hourly_rate = hourly_rate
        referee.location = referee_location
        referee.is_available = is_available
        referee.save()
        
        return Response({
            'success': True,
            'message': 'Referee profile created' if created else 'Referee profile updated',
            'referee': _referee_to_dict(referee)
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
        
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['GET'])
@permission_classes([AllowAny])
def get_referee_profile(request, user_id=None):
    """
    Get referee profile - by user_id if provided, otherwise own profile
    """
    try:
        if user_id:
            user = User.objects.get(id=user_id)
        else:
            user = request.user
        
        referee = Referee.objects.get(user=user)
        return Response({
            'success': True,
            'referee': _referee_to_dict(referee)
        })
        
    except Referee.DoesNotExist:
        return Response({'error': 'Referee not found'}, status=status.HTTP_404_NOT_FOUND)
    except User.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)




@api_view(['GET'])
@permission_classes([AllowAny])
def list_referees(request):
    """
    List all verified referees, optionally filtered by sport
    """
    try:
        sport = request.query_params.get('sport', '')
        available_only = request.query_params.get('available', 'true').lower() == 'true'
        
        queryset = Referee.objects.filter(verification_status='verified').select_related('user')
        
        if available_only:
            queryset = queryset.filter(is_available=True)
        
        if sport:
            queryset = queryset.filter(sports__icontains=sport)
        
        referees = [_referee_to_dict(r) for r in queryset]
        
        return Response({
            'success': True,
            'referees': referees
        })
        
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def book_referee(request):
    """
    Book a referee for a match
    """
    try:
        referee_id = request.data.get('referee_id')
        match_id = request.data.get('match_id')
        notes = sanitize_text(request.data.get('notes', ''))
        
        try:
            notes = validate_optional_string(notes, 5000, 'Notes')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        if not referee_id or not match_id:
            return Response({'error': 'referee_id and match_id are required'}, status=status.HTTP_400_BAD_REQUEST)
        
        referee = Referee.objects.get(id=referee_id)
        match = Match.objects.get(id=match_id)
        
        if not referee.is_available:
            return Response({'error': 'Referee is not available'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if already booked for this match
        if RefereeBooking.objects.filter(referee=referee, match=match).exists():
            return Response({'error': 'Referee already booked for this match'}, status=status.HTTP_400_BAD_REQUEST)
        
        booking = RefereeBooking.objects.create(
            referee=referee,
            match=match,
            booked_by=request.user,
            fee=referee.hourly_rate,
            notes=notes
        )
        
        # Create notification for referee
        Notification.objects.create(
            user=referee.user,
            notification_type='general',
            title='New Booking Request',
            message=f'{request.user.first_name} wants you to referee {match.title}',
            related_match=match
        )

        commission = referee_commission(booking.fee)
        record_transaction(
            'referee_commission', commission, payer=request.user,
            reference_type='referee_booking', reference_id=booking.id,
            note=f'Commission on referee booking for "{match.title}"',
        )

        return Response({
            'success': True,
            'message': 'Booking request sent',
            'booking': _booking_to_dict(booking),
            'platform_commission': str(commission),
        }, status=status.HTTP_201_CREATED)
        
    except Referee.DoesNotExist:
        return Response({'error': 'Referee not found'}, status=status.HTTP_404_NOT_FOUND)
    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['GET'])
def list_referee_bookings(request):
    """
    List bookings - as referee or as booker
    """
    try:
        as_referee = request.query_params.get('as', 'referee')
        
        if as_referee == 'referee':
            referee = Referee.objects.get(user=request.user)
            bookings = RefereeBooking.objects.filter(referee=referee).select_related('referee__user', 'match', 'booked_by')
        else:
            bookings = RefereeBooking.objects.filter(booked_by=request.user).select_related('referee__user', 'match', 'booked_by')
        
        return Response({
            'success': True,
            'bookings': [_booking_to_dict(b) for b in bookings]
        })
        
    except Referee.DoesNotExist:
        return Response({'success': True, 'bookings': []})
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def update_booking_status(request, booking_id):
    """
    Update booking status (accept/decline/complete)
    """
    try:
        new_status = request.data.get('status')
        valid_statuses = ['accepted', 'declined', 'completed', 'cancelled']
        
        if new_status not in valid_statuses:
            return Response({'error': 'Invalid status'}, status=status.HTTP_400_BAD_REQUEST)
        
        booking = RefereeBooking.objects.get(id=booking_id)
        
        # Only referee can accept/decline, only booker can cancel
        if new_status in ['accepted', 'declined']:
            if booking.referee.user != request.user:
                return Response({'error': 'Only referee can accept/decline'}, status=status.HTTP_403_FORBIDDEN)
        elif new_status == 'cancelled':
            if booking.booked_by != request.user:
                return Response({'error': 'Only booker can cancel'}, status=status.HTTP_403_FORBIDDEN)
        
        booking.status = new_status
        booking.save()
        
        # Update match if completed
        if new_status == 'completed':
            referee = booking.referee
            referee.total_matches += 1
            referee.save()
            
            Notification.objects.create(
                user=booking.booked_by,
                notification_type='general',
                title='Referee Assignment Confirmed',
                message=f'{referee.user.first_name} has completed refereeing {booking.match.title}'
            )
        
        return Response({
            'success': True,
            'message': f'Booking {new_status}',
            'booking': _booking_to_dict(booking)
        })
        
    except RefereeBooking.DoesNotExist:
        return Response({'error': 'Booking not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def rate_referee(request, booking_id):
    """
    Rate a referee after match completion
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
        
        booking = RefereeBooking.objects.get(id=booking_id, status='completed')
        
        if booking.booked_by != request.user:
            return Response({'error': 'Only the booker can rate'}, status=status.HTTP_403_FORBIDDEN)
        
        if RefereeRating.objects.filter(booking=booking).exists():
            return Response({'error': 'Already rated'}, status=status.HTTP_400_BAD_REQUEST)
        
        RefereeRating.objects.create(
            booking=booking,
            rated_by=request.user,
            rating=rating_value,
            comment=comment
        )
        
        # Update referee average rating
        referee = booking.referee
        ratings = RefereeRating.objects.filter(booking__referee=referee)
        avg = sum(r.rating for r in ratings) / len(ratings)
        referee.average_rating = round(avg, 2)
        referee.save()
        
        return Response({
            'success': True,
            'message': 'Rating submitted'
        })
        
    except RefereeBooking.DoesNotExist:
        return Response({'error': 'Booking not found or not completed'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Venue System ──
