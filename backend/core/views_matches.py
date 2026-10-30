import uuid
from decimal import Decimal

import requests as http_requests
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.conf import settings
from django.contrib.auth.models import User
from django.db.models import Q
from django.utils import timezone
from django.db import transaction
from datetime import datetime, timedelta
from .models import (
    UserProfile, Team, TeamMember, Match, MatchParticipant, MatchWaitlist, Notification,
    ChatMessage, PlayerRating, MatchResult, MatchResultConfirmation, Payment,
    Venue, VenueBooking, Favorite, MatchPot,
)
from .push import notify
from .entitlements import (
    can_host_match,
)
from .monetization import (
    host_fee_for, record_transaction, money,
    BOOKING_SLOT_HOURS, CANCEL_FULL_REFUND_HOURS, FIELD_SERVICE_FEE_ETB,
    HOST_CANCEL_STRIKE_LIMIT, HOST_SUSPENSION_DAYS,
)
from .escrow import (
    hold, release_match_funds, refund_percent_for,
    refund_participant, forfeit_no_shows, escrow_summary,
    all_players_confirmed, cancel_and_settle, venue_cancellation_fee,
)
from .payouts import credit_host
from .credits import account_for, credit_player, debit_player
from .reservations import reserve_for_match, release_reservation
from .match_pot import (
    active_participants, can_withdraw, claim_funded_spot, funding_summary,
    open_withdrawals, withdraw_participant,
)
from .serializers import (
    err_msg as _err_msg, display_name, match_summary, match_my, match_history,
)
from .validators import (
    SPORT_CHOICES, MATCH_TYPES, RESULT_TYPES, SKILL_LEVELS, validate_string, validate_optional_string,
    validate_int, validate_optional_int, validate_decimal, validate_enum, sanitize_text, validate_date_iso,
    validate_score, SensitiveWriteThrottle,
)


from .analytics import track
from .view_shared import (
    _apply_result_rankings,
)


@api_view(['PUT', 'PATCH'])
def edit_match(request, match_id):
    """
    Update match details. Only the organizer can edit.
    """
    try:
        match = Match.objects.get(id=match_id)

        if match.organizer.id != request.user.id:
            return Response(
                {'error': 'Only the organizer can edit this match'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            if 'title' in request.data:
                match.title = validate_string(request.data['title'], 200, 'Title')
            if 'description' in request.data:
                match.description = sanitize_text(validate_optional_string(request.data['description'], 5000, 'Description'))
            if 'location' in request.data:
                match.location = validate_optional_string(request.data['location'], 200, 'Location')
            if 'date_time' in request.data:
                match.date_time = validate_date_iso(request.data['date_time'], 'Date time')
            if 'max_players' in request.data:
                new_max = validate_int(request.data['max_players'], 2, 100, 'Max players')
                if new_max < match.current_players:
                    return Response(
                        {'error': f'Cannot set max_players below current players ({match.current_players})'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                match.max_players = new_max
            if 'price' in request.data:
                match.price = validate_decimal(request.data['price'], 0, 999999, 'Price')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        match.save()

        return Response({
            'message': 'Match updated successfully',
            'match': {
                'id': match.id,
                'title': match.title,
                'description': match.description,
                'location': match.location,
                'date_time': match.date_time.isoformat(),
                'max_players': match.max_players,
                'price': str(match.price),
            }
        }, status=status.HTTP_200_OK)

    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── In-Match Chat ──



@api_view(['GET'])
def get_match_chat(request, match_id):
    """
    Get chat messages for a match. Only participants can view.
    """
    try:
        match = Match.objects.get(id=match_id)

        # Check if user is participant or organizer
        is_participant = MatchParticipant.objects.filter(
            match=match, user=request.user
        ).exists()
        is_organizer = match.organizer.id == request.user.id

        if not is_participant and not is_organizer:
            return Response(
                {'error': 'You are not a participant of this match'},
                status=status.HTTP_403_FORBIDDEN
            )

        messages = list(
            ChatMessage.objects.filter(match=match).select_related('user')
            .order_by('-created_at', '-id')[:100]
        )
        messages.reverse()

        data = []
        for m in messages:
            user_name = f"{m.user.first_name} {m.user.last_name}".strip() or m.user.username
            data.append({
                'id': m.id,
                'user_id': m.user.id,
                'user_name': user_name,
                'message': m.message,
                'created_at': m.created_at.isoformat(),
            })

        return Response({'messages': data}, status=status.HTTP_200_OK)

    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def send_match_chat(request, match_id):
    """
    Send a chat message to a match. Only participants can send.
    """
    try:
        match = Match.objects.get(id=match_id)
        try:
            raw_message = request.data.get('message', '')
            message_text = sanitize_text(validate_string(raw_message, 10000, 'Message'))
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        # Check if user is participant
        is_participant = MatchParticipant.objects.filter(
            match=match, user=request.user
        ).exists()

        is_organizer = match.organizer.id == request.user.id

        if not is_participant and not is_organizer:
            return Response(
                {'error': 'You are not a participant of this match'},
                status=status.HTTP_403_FORBIDDEN
            )

        chat_message = ChatMessage.objects.create(
            match=match,
            user=request.user,
            message=message_text
        )

        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username

        # Notify all other match participants (single bulk insert)
        other_users = MatchParticipant.objects.filter(match=match).exclude(user=request.user).values_list('user_id', flat=True)
        notified = set(other_users)
        if match.organizer.id != request.user.id:
            notified.add(match.organizer.id)
        Notification.objects.bulk_create([
            Notification(
                user_id=uid,
                notification_type='chat_message',
                title=f'New message in {match.title}',
                message=f'{user_name}: {message_text[:100]}',
                related_match=match,
            )
            for uid in notified
        ])

        return Response({
            'message': 'Message sent',
            'chat_message': {
                'id': chat_message.id,
                'user_id': request.user.id,
                'user_name': user_name,
                'message': message_text,
                'created_at': chat_message.created_at.isoformat(),
            }
        }, status=status.HTTP_201_CREATED)

    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Team Chat ──



@api_view(['POST'])
def leave_match(request):
    """
    Leave a match (non-organizer only)
    Expected data: match_id
    """
    try:
        match_id = request.data.get('match_id')
        if not match_id:
            return Response({'error': 'Match ID is required'}, status=status.HTTP_400_BAD_REQUEST)

        promoted = None
        with transaction.atomic():
            match = Match.objects.select_for_update().get(id=match_id)

            # Organizer cannot leave – they must cancel
            if match.organizer.id == request.user.id:
                return Response({'error': 'Organizers cannot leave. Cancel the match instead.'}, status=status.HTTP_400_BAD_REQUEST)

            participant = MatchParticipant.objects.filter(match=match, user=request.user).first()
            if not participant:
                return Response({'error': 'You are not in this match'}, status=status.HTTP_400_BAD_REQUEST)

            if match.booking_status == 'confirmed':
                return Response({
                    'error': 'The field is already booked — cancel is not available. '
                             'Use withdraw to give up your spot; no refund is issued.',
                    'code': 'use_withdraw',
                }, status=status.HTTP_400_BAD_REQUEST)

            if participant.withdrawn_at is not None:
                return Response({'error': 'You already withdrew from this match'},
                                status=status.HTTP_400_BAD_REQUEST)

            # Refund the share per the cancellation window before removing them.
            refund_pct = refund_percent_for(match)
            refunded_amount = money(0)
            if participant.payment_status == 'held':
                refunded_amount = refund_participant(
                    participant, percent=refund_pct, reason='Player left the match')

            participant.delete()
            match.current_players = max(0, match.current_players - 1)
            match.save()

            # Auto-promote the first person on the waitlist
            if match.is_active and match.current_players < match.max_players:
                nxt = MatchWaitlist.objects.filter(match=match).order_by('created_at').first()
                if nxt:
                    promoted = nxt.user
                    MatchParticipant.objects.create(match=match, user=promoted)
                    match.current_players += 1
                    match.save()
                    nxt.delete()

        if promoted is not None:
            notify(
                promoted,
                'waitlist_promoted',
                "You're in!",
                f'A spot opened in "{match.title}" — you have been added.',
                match=match,
            )

        # Notify organizer
        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        Notification.objects.create(
            user=match.organizer,
            notification_type='match_left',
            title='Player Left',
            message=f'{user_name} left your match "{match.title}".',
            related_match=match,
        )

        return Response({'message': 'You have left the match',
                         'refund_percent': refund_pct,
                         'refunded': str(refunded_amount)}, status=status.HTTP_200_OK)

    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def cancel_match(request):
    """
    Cancel a match (organizer only). Notifies all participants.
    Expected data: match_id
    """
    try:
        match_id = request.data.get('match_id')
        if not match_id:
            return Response({'error': 'Match ID is required'}, status=status.HTTP_400_BAD_REQUEST)

        match = Match.objects.get(id=match_id)

        if match.organizer.id != request.user.id:
            return Response({'error': 'Only the organizer can cancel this match'}, status=status.HTTP_403_FORBIDDEN)

        # A played match can't be cancelled.
        result = MatchResult.objects.filter(match=match).first()
        if result and result.status == 'confirmed':
            return Response({'error': 'This match has been played and confirmed — it cannot be cancelled'},
                            status=status.HTTP_400_BAD_REQUEST)

        if not match.is_active:
            return Response({'error': 'Match is already cancelled'}, status=status.HTTP_400_BAD_REQUEST)

        if match.booking_status == 'confirmed':
            return Response({
                'error': 'The field is already booked. Withdraw from the match instead; '
                         'the match can stay booked with the remaining players.',
                'code': 'use_withdraw',
            }, status=status.HTTP_400_BAD_REQUEST)

        hours_to_kickoff = (match.date_time - timezone.now()).total_seconds() / 3600
        late = hours_to_kickoff < CANCEL_FULL_REFUND_HOURS

        # Host cancels before the field is booked: keep 20% of the host's share.
        host_fee_kept = money(0)
        host_participant = MatchParticipant.objects.filter(
            match=match, user=request.user).first()
        if host_participant and host_participant.payment_status == 'held':
            host_share = money(host_participant.amount_paid or match.price)
            host_fee_kept = money(host_share * Decimal('0.20'))
            refund_participant(
                host_participant, percent=80,
                reason='Host cancelled the match (20% fee)')
            if host_fee_kept > 0:
                record_transaction(
                    'cancellation_fee', host_fee_kept, payer=request.user,
                    reference_type='match', reference_id=match.id,
                    status='collected',
                    note='Host cancellation fee (20% of host share)',
                )

        # Cancel the venue booking (if any) and work out the venue's fee.
        venue_fee = money(0)
        booking = VenueBooking.objects.filter(match=match).first()
        if booking and booking.status != 'cancelled':
            venue_fee = venue_cancellation_fee(booking)
            booking.status = 'cancelled'
            booking.save(update_fields=['status'])

        settlement = cancel_and_settle(match, reason='Cancelled by the organizer', venue_fee=venue_fee)

        match.is_active = False
        match.booking_status = 'cancelled'
        match.cancelled_reason = 'Cancelled by organizer'
        match.cancelled_at = timezone.now()
        match.save(update_fields=['is_active', 'booking_status', 'cancelled_reason', 'cancelled_at'])

        # Only the host is penalised.
        profile = UserProfile.get_or_create_for_user(request.user)
        if late:
            profile.host_cancel_count += 1
        if profile.host_cancel_count >= HOST_CANCEL_STRIKE_LIMIT:
            profile.host_suspended_until = timezone.now() + timedelta(days=HOST_SUSPENSION_DAYS)
        profile.save(update_fields=['host_cancel_count', 'host_suspended_until'])

        for p in MatchParticipant.objects.filter(match=match).exclude(user=request.user).select_related('user'):
            notify(
                p.user,
                'match_cancelled',
                'Match cancelled by the host',
                f'"{match.title}" was cancelled by the organizer. '
                f'Your share (Br {p.amount_paid}) has been refunded.',
                match=match,
            )

        return Response({
            'message': 'Match cancelled — players refunded',
            'refunded': str(settlement['refunded']),
            'host_fee_kept': str(host_fee_kept),
            'venue_fee': str(venue_fee),
            'host_penalty': str(settlement['penalty']),
            'host_strikes': profile.host_cancel_count,
            'suspended_until': profile.host_suspended_until.isoformat() if profile.host_suspended_until else None,
        }, status=status.HTTP_200_OK)

    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Feature 2: Leave Team ──



@api_view(['POST'])
def withdraw_match(request, match_id):
    """Give up a spot after the field is booked. No refund; the spot stays funded."""
    if not request.user.is_authenticated:
        return Response({'error': 'Authentication required'},
                        status=status.HTTP_401_UNAUTHORIZED)
    match = Match.objects.filter(id=match_id).first()
    if match is None:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)
    try:
        result = withdraw_participant(match, request.user)
    except ValueError as exc:
        return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

    track(request.user, 'match_withdrew', {
        'match_id': match.id, 'share': result['share_amount'],
    })
    return Response({
        'success': True,
        'message': 'You withdrew. Your share stays in the pot to fund a replacement.',
        'funding': funding_summary(match),
        **result,
    })


@api_view(['GET'])
def get_match_history(request):
    """
    Get past matches for the logged-in user (matches whose date_time < now)
    """
    try:
        now = timezone.now()

        participated_ids = MatchParticipant.objects.filter(
            user=request.user
        ).values_list('match_id', flat=True)

        past_matches = Match.objects.filter(
            id__in=participated_ids,
            date_time__lt=now,
        ).select_related('organizer').order_by('-date_time')[:200]

        matches_data = [match_history(match, request.user) for match in past_matches]

        return Response({'matches': matches_data}, status=status.HTTP_200_OK)

    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Feature 4: Notifications ──



@api_view(['GET'])
@permission_classes([AllowAny])
def search_matches(request):
    """
    Search & filter matches.
    Query params: sport, location, min_price, max_price, date_from, date_to, q (text search)
    """
    try:
        qs = Match.objects.filter(
            is_active=True,
            date_time__gte=timezone.now(),
        ).select_related('organizer', 'organizer__profile')

        sport = request.query_params.get('sport')
        if sport:
            qs = qs.filter(sport__iexact=sport)

        skill = request.query_params.get('skill')
        if skill and skill in SKILL_LEVELS and skill != 'any':
            qs = qs.filter(skill_level=skill)

        location = request.query_params.get('location')
        if location:
            qs = qs.filter(location__icontains=location)

        min_price = request.query_params.get('min_price')
        if min_price is not None:
            try:
                qs = qs.filter(price__gte=float(min_price))
            except ValueError:
                pass

        max_price = request.query_params.get('max_price')
        if max_price is not None:
            try:
                qs = qs.filter(price__lte=float(max_price))
            except ValueError:
                pass

        date_from = request.query_params.get('date_from')
        if date_from:
            try:
                qs = qs.filter(date_time__gte=datetime.fromisoformat(date_from))
            except (ValueError, TypeError):
                pass

        date_to = request.query_params.get('date_to')
        if date_to:
            try:
                qs = qs.filter(date_time__lte=datetime.fromisoformat(date_to))
            except (ValueError, TypeError):
                pass

        q = request.query_params.get('q')
        if q:
            qs = qs.filter(
                Q(title__icontains=q) | Q(location__icontains=q) | Q(description__icontains=q)
            )

        qs = qs.prefetch_related('participants__user').order_by(
            '-organizer__profile__is_premium', 'date_time')
        matches_data = [match_summary(match) for match in qs[:50]]

        return Response({'matches': matches_data}, status=status.HTTP_200_OK)

    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)



@api_view(['POST'])
def create_match(request):
    """
    Create a new match
    Expected data: title, sport, description, location, date_time, max_players, price
    """
    try:
        try:
            title = validate_string(request.data.get('title'), 200, 'Title')
            sport = validate_enum(request.data.get('sport', 'other'), SPORT_CHOICES, 'Sport')
            description = sanitize_text(validate_optional_string(request.data.get('description', ''), 5000, 'Description'))
            location = validate_string(request.data.get('location'), 200, 'Location')
            date_time = validate_date_iso(request.data.get('date_time'), 'Date/time')
            max_players = validate_int(request.data.get('max_players', 10), 2, 100, 'Max players')
            min_players = validate_int(request.data.get('min_players', 0), 0, 100, 'Min players')
            price = validate_decimal(request.data.get('price', 0), 0, 999999, 'Price')
            skill_level = validate_enum(request.data.get('skill_level', 'any'), SKILL_LEVELS, 'skill_level')
            team_id = request.data.get('team_id')
            venue_id = request.data.get('venue_id')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        team = None
        if team_id:
            team = Team.objects.get(id=team_id)

        venue = None
        if venue_id:
            try:
                venue = Venue.objects.get(id=venue_id)
            except Venue.DoesNotExist:
                return Response({'error': 'Venue not found'}, status=status.HTTP_404_NOT_FOUND)

        profile = UserProfile.get_or_create_for_user(request.user)
        if profile.host_suspended_until and profile.host_suspended_until > timezone.now():
            return Response({
                'error': 'You are suspended from hosting after repeated cancellations. '
                         f'You can host again on {profile.host_suspended_until:%Y-%m-%d}.',
                'suspended_until': profile.host_suspended_until.isoformat(),
            }, status=status.HTTP_403_FORBIDDEN)

        if not can_host_match(request.user):
            return Response({
                'error': 'Free accounts can host 2 matches per month. Upgrade to Premium for unlimited hosting.',
                'upgrade_required': True,
            }, status=status.HTTP_402_PAYMENT_REQUIRED)

        if min_players > max_players:
            return Response({'error': 'min_players cannot be greater than max_players'},
                            status=status.HTTP_400_BAD_REQUEST)

        match = Match.objects.create(
            title=title,
            sport=sport,
            description=description,
            location=location,
            date_time=date_time,
            max_players=max_players,
            min_players=min_players,
            price=price,
            skill_level=skill_level,
            organizer=request.user,
            team=team,
            venue=venue,
            current_players=1,
        )
        track(request.user, 'match_created', {
            'sport': sport, 'price': float(price), 'max_players': max_players,
        })

        # Add organizer as participant
        MatchParticipant.objects.create(
            match=match,
            user=request.user
        )

        host_fee = host_fee_for(request.user)
        if host_fee > 0:
            record_transaction(
                'host_fee', host_fee, payer=request.user,
                reference_type='match', reference_id=match.id,
                note=f'Host fee for "{match.title}"',
            )

        return Response({
            'message': 'Match created successfully',
            'host_fee': str(host_fee),
            'match': {
                'id': match.id,
                'title': match.title,
                'sport': match.sport,
                'description': match.description,
                'location': match.location,
                'date_time': match.date_time.isoformat(),
                'max_players': match.max_players,
                'min_players': match.min_players,
                'current_players': match.current_players,
                'price': str(match.price),
                'skill_level': match.skill_level,
                'organizer_id': match.organizer.id,
                'venue_id': match.venue_id,
                'booking_status': match.booking_status,
            }
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )




@api_view(['GET'])
@permission_classes([AllowAny])
def get_matches(request):
    """
    Get all active matches
    """
    try:
        qs = Match.objects.filter(
            is_active=True,
            date_time__gte=timezone.now()
        )
        skill = request.query_params.get('skill')
        if skill and skill in SKILL_LEVELS and skill != 'any':
            qs = qs.filter(skill_level=skill)

        matches = qs.select_related('organizer', 'organizer__profile').prefetch_related(
            'participants__user').order_by(
            '-organizer__profile__is_premium', 'date_time')[:100]

        matches_data = [match_summary(match) for match in matches]

        return Response({
            'matches': matches_data
        }, status=status.HTTP_200_OK)

    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )




@api_view(['GET'])
def get_my_matches(request):
    """
    Get matches for the current user with role and time filters.
    Query params:
      - role: all | hosted | joined | saved
      - status: all | upcoming | past
    """
    try:
        role = (request.query_params.get('role') or 'all').strip().lower()
        status_filter = (request.query_params.get('status') or 'all').strip().lower()
        now = timezone.now()

        joined_ids = set(
            MatchParticipant.objects.filter(user=request.user).values_list('match_id', flat=True)
        )
        saved_ids = set(
            Favorite.objects.filter(user=request.user, favorite_type='match').values_list('object_id', flat=True)
        )

        queryset = Match.objects.select_related('organizer', 'result').prefetch_related(
            'participants__user').all()

        if role == 'hosted':
            queryset = queryset.filter(organizer=request.user)
        elif role == 'joined':
            queryset = queryset.filter(participants__user=request.user)
        elif role == 'saved':
            queryset = queryset.filter(id__in=saved_ids)
        else:
            queryset = queryset.filter(
                Q(organizer=request.user) |
                Q(participants__user=request.user) |
                Q(id__in=saved_ids)
            )

        if status_filter == 'upcoming':
            queryset = queryset.filter(date_time__gte=now)
        elif status_filter == 'past':
            queryset = queryset.filter(date_time__lt=now)

        if status_filter == 'upcoming':
            queryset = queryset.distinct().order_by('date_time')
        elif status_filter == 'past':
            queryset = queryset.distinct().order_by('-date_time')
        else:
            queryset = queryset.distinct().order_by('-date_time')

        my_team_ids = set(
            Team.objects.filter(owner=request.user).values_list('id', flat=True)
        ) | set(
            TeamMember.objects.filter(user=request.user).values_list('team_id', flat=True)
        )

        matches_data = [
            match_my(match, request.user, joined_ids, saved_ids, my_team_ids)
            for match in queryset[:200]
        ]

        return Response({
            'matches': matches_data
        }, status=status.HTTP_200_OK)

    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )




@api_view(['POST'])
def join_match(request):
    """
    Join a match
    Expected data: match_id
    """
    try:
        match_id = request.data.get('match_id')
        
        if not match_id:
            return Response(
                {'error': 'Match ID is required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        with transaction.atomic():
            match = Match.objects.select_for_update().get(id=match_id)

            if not match.is_active:
                return Response({'error': 'This match has been cancelled'},
                                status=status.HTTP_400_BAD_REQUEST)

            if match.date_time <= timezone.now():
                return Response({'error': 'This match has already started'},
                                status=status.HTTP_400_BAD_REQUEST)

            if match.booking_status == 'confirmed':
                try:
                    funded = claim_funded_spot(match, request.user)
                except ValueError as exc:
                    return Response(
                        {'error': str(exc), 'funded_spot': True},
                        status=status.HTTP_400_BAD_REQUEST)
                track(request.user, 'match_joined', {
                    'match_id': match.id, 'sport': match.sport, 'price': 0,
                    'funded': True,
                })
                return Response({
                    'message': 'Joined a funded spot — no payment needed',
                    'funded': True,
                    'match': {'id': match.id, 'title': match.title},
                    **funded,
                }, status=status.HTTP_200_OK)

            # Check if already a participant
            if MatchParticipant.objects.filter(match=match, user=request.user).exists():
                return Response(
                    {'error': 'You have already joined this match'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Check if spots available (atomic: locked row)
            if match.current_players >= match.max_players:
                MatchWaitlist.objects.get_or_create(match=match, user=request.user)
                return Response({
                    'message': "Match is full — you're on the waitlist",
                    'waitlisted': True,
                    'match': {'id': match.id, 'title': match.title},
                }, status=status.HTTP_200_OK)

            # Add user as participant (and clear any stale waitlist entry)
            MatchParticipant.objects.create(
                match=match,
                user=request.user
            )
            MatchWaitlist.objects.filter(match=match, user=request.user).delete()

            match.current_players += 1
            match.save()

        # Notify organizer
        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        Notification.objects.create(
            user=match.organizer,
            notification_type='match_joined',
            title='New Player',
            message=f'{user_name} joined your match "{match.title}".',
            related_match=match,
        )

        # Tell the host the moment the minimum roster is met (field can be booked).
        if (match.min_players
                and match.current_players >= match.min_players
                and match.current_players - 1 < match.min_players):
            notify(
                match.organizer,
                'general',
                'Ready to book the field',
                f'"{match.title}" now has {match.current_players} players — '
                f'the minimum of {match.min_players} is met. You can book the field.',
                match=match,
            )

        track(request.user, 'match_joined', {
            'match_id': match.id, 'sport': match.sport, 'price': float(match.price),
        })

        return Response({
            'message': 'Successfully joined the match',
            'match': {
                'id': match.id,
                'title': match.title,
            }
        }, status=status.HTTP_200_OK)

    except Match.DoesNotExist:
        return Response(
            {'error': 'Match not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )




@api_view(['GET'])
@permission_classes([AllowAny])
def get_match_details(request, match_id):
    """
    Get match details including participants with their info
    """
    try:
        match = Match.objects.select_related('organizer').get(id=match_id)

        # Get participants with user details
        participants = MatchParticipant.objects.filter(
            match=match
        ).select_related('user', 'user__profile')

        participant = None
        is_participant = False
        is_organizer = False
        if request.user and request.user.is_authenticated:
            participant = MatchParticipant.objects.filter(
                match=match, user=request.user).first()
            is_participant = participant is not None
            is_organizer = match.organizer.id == request.user.id

        participants_data = []
        for p in participants:
            phone = ''
            try:
                phone = p.user.profile.phone
            except UserProfile.DoesNotExist:
                pass

            participant_info = {
                'id': p.user.id,
                'name': display_name(p.user),
                'joined_at': p.joined_at.isoformat(),
                'is_organizer': p.user.id == match.organizer.id,
                'withdrawn': p.withdrawn_at is not None,
            }
            if is_organizer or p.user.id == request.user.id:
                participant_info['email'] = p.user.email
                participant_info['phone'] = phone
                participant_info['payment_status'] = p.payment_status
            participants_data.append(participant_info)

        organizer_name = display_name(match.organizer)
        funded_spots = open_withdrawals(match).count()
        has_withdrawn = bool(participant and participant.withdrawn_at)
        can_withdraw_flag = bool(
            participant and request.user.is_authenticated
            and can_withdraw(match, request.user))

        return Response({
            'match': {
                'id': match.id,
                'title': match.title,
                'sport': match.sport,
                'description': match.description,
                'location': match.location,
                'date_time': match.date_time.isoformat(),
                'max_players': match.max_players,
                'min_players': match.min_players,
                'current_players': match.current_players,
                'spots_left': match.max_players - match.current_players,
                'price': str(match.price),
                'skill_level': match.skill_level,
                'organizer_id': match.organizer.id,
                'organizer_name': organizer_name,
                'venue_id': match.venue_id,
                'venue_name': match.venue.name if match.venue else None,
                'venue_address': match.venue.address if match.venue else None,
                'venue_city': match.venue.city if match.venue else None,
                'booking_status': match.booking_status,
                'is_booked': match.booking_status == 'confirmed',
                'has_withdrawn': has_withdrawn,
                'can_withdraw': can_withdraw_flag,
                'open_funded_spots': funded_spots,
                'can_join_funded': (
                    match.booking_status == 'confirmed' and funded_spots > 0
                    and participant is None and match.is_active
                    and match.date_time > timezone.now()
                ),
                'my_payment_status': participant.payment_status if participant else None,
                'my_booking_confirmed': participant.booking_confirmed if participant else False,
                'funding': funding_summary(match),
                'is_organizer': is_organizer,
                'is_participant': is_participant,
                'escrow': escrow_summary(match) if is_organizer else None,
                'waitlist_count': match.waitlist.count(),
                'team_id': match.team.id if match.team else None,
                'team_name': match.team.name if match.team else None,
            },
            'participants': participants_data,
        }, status=status.HTTP_200_OK)

    except Match.DoesNotExist:
        return Response(
            {'error': 'Match not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )




@api_view(['GET', 'POST'])
@permission_classes([AllowAny])
def match_ratings(request, match_id):
    """Get or submit ratings for a match"""
    try:
        match = Match.objects.get(id=match_id)
    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)

    if request.method == 'GET':
        ratings = PlayerRating.objects.filter(match=match).select_related('rater', 'rated_user')
        ratings_data = []
        for r in ratings:
            ratings_data.append({
                'id': r.id,
                'rater_id': r.rater.id,
                'rater_name': r.rater.username,
                'rated_user_id': r.rated_user.id,
                'rated_user_name': r.rated_user.username,
                'rating': r.rating,
                'comment': r.comment,
                'created_at': r.created_at.isoformat(),
            })
        return Response({'ratings': ratings_data}, status=status.HTTP_200_OK)

    elif request.method == 'POST':
        rater = request.user
        if not rater.is_authenticated:
            return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

        rated_user_id = request.data.get('rated_user_id')
        rating = request.data.get('rating')
        comment = sanitize_text(request.data.get('comment', ''))

        if not rated_user_id or rating is None:
            return Response({'error': 'rated_user_id and rating are required'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            rating_value = int(rating)
        except (TypeError, ValueError):
            return Response({'error': 'rating must be an integer between 1 and 5'},
                            status=status.HTTP_400_BAD_REQUEST)

        try:
            comment = validate_optional_string(comment, 5000, 'Comment')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        try:
            rated_user = User.objects.get(id=rated_user_id)
        except (User.DoesNotExist, ValueError, TypeError):
            return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

        if rating_value < 1 or rating_value > 5:
            return Response({'error': 'Rating must be between 1 and 5'}, status=status.HTTP_400_BAD_REQUEST)

        is_participant = MatchParticipant.objects.filter(match=match, user=rater).exists()
        if not is_participant:
            return Response({'error': 'You must be a participant to rate others'}, status=status.HTTP_403_FORBIDDEN)

        if rated_user.id == rater.id:
            return Response({'error': 'You cannot rate yourself'}, status=status.HTTP_400_BAD_REQUEST)

        if not MatchParticipant.objects.filter(match=match, user=rated_user).exists():
            return Response({'error': 'rated_user is not a participant of this match'},
                            status=status.HTTP_400_BAD_REQUEST)

        rating_obj, created = PlayerRating.objects.update_or_create(
            match=match,
            rater=rater,
            rated_user=rated_user,
            defaults={'rating': rating_value, 'comment': comment}
        )

        return Response({
            'message': 'Rating submitted successfully',
            'rating': {
                'id': rating_obj.id,
                'rated_user_id': rated_user.id,
                'rated_user_name': rated_user.username,
                'rating': rating_obj.rating,
                'comment': rating_obj.comment,
            }
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)




RESULT_EDIT_WINDOW_HOURS = 48


def _needed_confirmations(participant_count):
    """Majority of the *other* participants must confirm (the organizer submitted)."""
    return max(1, ((participant_count - 1) // 2) + 1)


def _result_to_dict(result):
    return {
        'id': result.id,
        'match_id': result.match_id,
        'match_type': result.match_type,
        'result_type': result.result_type,
        'winner_team_id': result.winner_team_id,
        'winner_user_id': result.winner_user_id,
        'team1_id': result.team1_id,
        'team2_id': result.team2_id,
        'winning_group': result.winning_group,
        'mvp_user_id': result.mvp_user_id,
        'score': result.score,
        'status': result.status,
        'no_show_user_ids': result.no_show_list,
        'confirmed_at': result.confirmed_at.isoformat() if result.confirmed_at else None,
        'notes': result.notes,
        'created_by': result.created_by.username if result.created_by else None,
        'created_at': result.created_at.isoformat(),
    }


@api_view(['GET', 'POST', 'PUT'])
@permission_classes([AllowAny])
def match_result(request, match_id):
    """Get or submit a match result.

    Only the organizer can submit. Results start as `pending`, are confirmed by
    the participants, and rankings are applied only once confirmed.
    """
    try:
        match = Match.objects.get(id=match_id)
    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)

    if request.method == 'GET':
        result = MatchResult.objects.filter(match=match).first()
        if not result:
            return Response({'result': None}, status=status.HTTP_200_OK)
        total = MatchParticipant.objects.filter(match=match).count()
        return Response({
            'result': _result_to_dict(result),
            'confirmations': {
                'confirmed': result.confirmations.filter(status='confirmed').count(),
                'disputed': result.confirmations.filter(status='disputed').count(),
                'needed': _needed_confirmations(total),
            },
        }, status=status.HTTP_200_OK)

    user = request.user
    if not user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    if match.organizer.id != user.id:
        return Response({'error': 'Only the match organizer can set results'}, status=status.HTTP_403_FORBIDDEN)

    existing = MatchResult.objects.filter(match=match).first()
    if existing:
        if existing.status == 'confirmed':
            return Response({'error': 'This result is confirmed and can no longer be edited'},
                            status=status.HTTP_400_BAD_REQUEST)
        if timezone.now() - existing.created_at > timedelta(hours=RESULT_EDIT_WINDOW_HOURS):
            return Response({
                'error': f'Results can only be edited within {RESULT_EDIT_WINDOW_HOURS}h of the match',
            }, status=status.HTTP_400_BAD_REQUEST)

    try:
        match_type = validate_enum(request.data.get('match_type', 'pickup'), MATCH_TYPES, 'match_type')
        result_type = validate_enum(request.data.get('result_type', 'individual'), RESULT_TYPES, 'result_type')
        winner_team_id = validate_optional_int(request.data.get('winner_team_id'), 1, 999999, 'winner_team_id')
        winner_user_id = validate_optional_int(request.data.get('winner_user_id'), 1, 999999, 'winner_user_id')
        team1_id = validate_optional_int(request.data.get('team1_id'), 1, 999999, 'team1_id')
        team2_id = validate_optional_int(request.data.get('team2_id'), 1, 999999, 'team2_id')
        winning_group = validate_optional_string(request.data.get('winning_group', ''), 10, 'winning_group')
        mvp_user_id = validate_optional_int(request.data.get('mvp_user_id'), 1, 999999, 'mvp_user_id')
        score = validate_score(request.data.get('score', ''))
        notes = sanitize_text(validate_optional_string(request.data.get('notes', ''), 5000, 'notes'))
        team_groups = request.data.get('team_groups')
        raw_no_shows = request.data.get('no_show_user_ids') or []
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

    participants = list(MatchParticipant.objects.filter(match=match))
    participant_ids = {p.user_id for p in participants}

    if winning_group and winning_group not in ('A', 'B'):
        return Response({'error': "winning_group must be 'A' or 'B'"},
                        status=status.HTTP_400_BAD_REQUEST)

    if (match_type == 'team_vs_team' and result_type != 'draw'
            and winning_group not in ('A', 'B') and not winner_team_id):
        return Response({'error': 'Provide winner_team_id or winning_group for team vs team matches'},
                        status=status.HTTP_400_BAD_REQUEST)

    if team1_id and team2_id and team1_id == team2_id:
        return Response({'error': 'team1_id and team2_id must be different'},
                        status=status.HTTP_400_BAD_REQUEST)

    if (match_type == 'team_vs_team' and result_type != 'draw'
            and winner_team_id and team1_id and team2_id
            and winner_team_id not in (team1_id, team2_id)):
        return Response({'error': 'winner_team_id must be team1_id or team2_id'},
                        status=status.HTTP_400_BAD_REQUEST)

    if result_type != 'draw':
        if match_type == 'pickup' and not winner_user_id:
            return Response({'error': 'winner_user_id is required for non-draw pickup matches'},
                            status=status.HTTP_400_BAD_REQUEST)
        if match_type == 'pickup' and winner_user_id and winner_user_id not in participant_ids:
            return Response({'error': 'winner_user_id is not a participant of this match'},
                            status=status.HTTP_400_BAD_REQUEST)

    if mvp_user_id and mvp_user_id not in participant_ids:
        return Response({'error': 'mvp_user_id is not a participant of this match'},
                        status=status.HTTP_400_BAD_REQUEST)

    no_show_ids = []
    if isinstance(raw_no_shows, (list, tuple)):
        for x in raw_no_shows:
            if str(x).strip().isdigit() and int(x) in participant_ids:
                no_show_ids.append(int(x))

    with transaction.atomic():
        result, created = MatchResult.objects.update_or_create(
            match=match,
            defaults={
                'match_type': match_type,
                'result_type': result_type,
                'winner_team_id': winner_team_id,
                'winner_user_id': winner_user_id,
                'team1_id': team1_id,
                'team2_id': team2_id,
                'winning_group': winning_group,
                'mvp_user_id': mvp_user_id,
                'score': score,
                'no_show_user_ids': ','.join(str(x) for x in no_show_ids),
                'notes': notes,
                'created_by': user,
                'status': 'pending',
                'rankings_applied': False,
                'confirmed_at': None,
            },
        )
        # A re-submitted result resets any previous votes.
        result.confirmations.all().delete()

        if team_groups and isinstance(team_groups, dict):
            for group, user_ids in team_groups.items():
                if group not in ('A', 'B'):
                    continue
                for uid in user_ids:
                    MatchParticipant.objects.filter(match=match, user_id=uid).update(team_group=group)

        # Solo matches have nobody to confirm.
        if len(participants) <= 1:
            result.status = 'confirmed'
            result.confirmed_at = timezone.now()
            result.save(update_fields=['status', 'confirmed_at'])
            _apply_result_rankings(match, result)

    pending = result.status == 'pending'
    return Response({
        'message': 'Match result saved — awaiting player confirmation' if pending else 'Match result saved',
        'result': _result_to_dict(result),
        'confirmations': {
            'confirmed': 0,
            'disputed': 0,
            'needed': _needed_confirmations(len(participants)),
        },
    }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)


@api_view(['POST'])
def confirm_match_result(request, match_id):
    """A participant confirms or disputes the recorded result."""
    try:
        match = Match.objects.get(id=match_id)
    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)

    result = MatchResult.objects.filter(match=match).first()
    if not result:
        return Response({'error': 'No result recorded yet'}, status=status.HTTP_404_NOT_FOUND)

    if not MatchParticipant.objects.filter(match=match, user=request.user).exists():
        return Response({'error': 'Only match participants can confirm the result'},
                        status=status.HTTP_403_FORBIDDEN)

    if result.status == 'confirmed':
        return Response({'success': True, 'status': 'confirmed', 'message': 'Result already confirmed'})

    try:
        vote = validate_enum(request.data.get('status', 'confirmed'), {'confirmed', 'disputed'}, 'status')
        note = sanitize_text(validate_optional_string(request.data.get('note', ''), 300, 'Note'))
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

    MatchResultConfirmation.objects.update_or_create(
        result=result, user=request.user, defaults={'status': vote, 'note': note})

    if vote == 'disputed':
        result.status = 'disputed'
        result.save(update_fields=['status'])
        notify(match.organizer, 'match_result_disputed', 'Result disputed',
               f'"{match.title}" result was disputed by a player.', match=match)
        return Response({'success': True, 'status': 'disputed', 'message': 'Result disputed'})

    total = MatchParticipant.objects.filter(match=match).count()
    confirms = result.confirmations.filter(status='confirmed').count()
    needed = _needed_confirmations(total)

    if confirms >= needed:
        result.status = 'confirmed'
        result.confirmed_at = timezone.now()
        result.save(update_fields=['status', 'confirmed_at'])
        forfeited = forfeit_no_shows(match, result.no_show_list)
        released = release_match_funds(match)
        _apply_result_rankings(match, result)
        return Response({'success': True, 'status': 'confirmed',
                         'released': str(released), 'forfeited': str(forfeited),
                         'message': 'Result confirmed — rankings updated'})

    return Response({
        'success': True,
        'status': 'pending',
        'message': f'Thanks! {confirms}/{needed} confirmations',
        'confirmations': {'confirmed': confirms, 'needed': needed},
    })


@api_view(['POST'])
def mark_match_payments(request, match_id):
    """Organizer records which players have paid their share."""
    try:
        match = Match.objects.get(id=match_id)
    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)

    if match.organizer.id != request.user.id:
        return Response({'error': 'Only the organizer can record payments'}, status=status.HTTP_403_FORBIDDEN)

    raw = request.data.get('paid_user_ids') or []
    paid_ids = [int(x) for x in raw if str(x).strip().isdigit()] if isinstance(raw, (list, tuple)) else []

    participant_ids = set(MatchParticipant.objects.filter(match=match).values_list('user_id', flat=True))
    paid_ids = [uid for uid in paid_ids if uid in participant_ids]

    # Never clobber escrow that was actually settled through the gateway or
    # that has already been refunded/released.
    gateway_paid_ids = set(Payment.objects.filter(
        payment_type='match_share', reference_type='match',
        reference_id=match.id, status='success',
    ).values_list('user_id', flat=True))
    locked_statuses = ('released', 'refunded', 'partially_refunded', 'forfeited')

    editable = MatchParticipant.objects.filter(match=match).exclude(
        Q(user_id__in=gateway_paid_ids) | Q(payment_status__in=locked_statuses))
    editable.update(paid=False, paid_at=None, amount_paid=0, payment_status='unpaid')

    now = timezone.now()
    if paid_ids:
        MatchParticipant.objects.filter(match=match, user_id__in=paid_ids).exclude(
            Q(user_id__in=gateway_paid_ids) | Q(payment_status__in=locked_statuses)
        ).update(paid=True, paid_at=now, amount_paid=match.price, payment_status='held')

    if match.organizer_id in paid_ids and match.venue and \
            match.booking_status != 'confirmed':
        try:
            reserve_for_match(match)
        except ValueError:
            pass

    paid_count = MatchParticipant.objects.filter(match=match, paid=True).count()
    total = len(participant_ids)
    return Response({
        'success': True,
        'paid_count': paid_count,
        'total': total,
        'collected': str(match.price * paid_count),
        'expected': str(match.price * total),
    })


@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def pay_match_share(request, match_id):
    """Start an escrow payment for the caller's share of a match."""
    try:
        match = Match.objects.get(id=match_id)
    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)

    if not match.is_active:
        return Response({'error': 'This match is no longer active'}, status=status.HTTP_400_BAD_REQUEST)

    participant = MatchParticipant.objects.filter(match=match, user=request.user).first()
    if not participant:
        return Response({'error': 'Join the match before paying'}, status=status.HTTP_400_BAD_REQUEST)

    if participant.payment_status in ('held', 'released'):
        return Response({'success': True, 'already_paid': True,
                         'payment_status': participant.payment_status})

    if match.price <= 0:
        return Response({'success': False, 'message': 'This match is free - no payment needed'},
                        status=status.HTTP_400_BAD_REQUEST)

    price = money(match.price)
    credit_used = money(participant.credit_applied or 0)
    if credit_used > price:
        credit_used = price
        participant.credit_applied = price
        participant.save(update_fields=['credit_applied'])

    if credit_used == 0:
        account = account_for(request.user)
        candidate = money(min(account.balance, price))
        if candidate > 0:
            try:
                debit_player(
                    request.user, candidate, 'used', match=match,
                    note=f'Credit applied to "{match.title}"',
                )
                participant.credit_applied = candidate
                participant.save(update_fields=['credit_applied'])
                credit_used = candidate
            except ValueError:
                credit_used = money(0)

    amount_due = money(price - credit_used)

    def _return_credit():
        if credit_used > 0:
            credit_player(
                request.user, credit_used, 'adjustment', match=match,
                note='Credit returned — payment was not started',
            )
            participant.credit_applied = money(0)
            participant.save(update_fields=['credit_applied'])

    if request.user.id == match.organizer_id and match.venue and \
            match.booking_status != 'confirmed':
        try:
            reserve_for_match(match)
        except ValueError as exc:
            _return_credit()
            return Response({'error': str(exc)}, status=status.HTTP_409_CONFLICT)

    if amount_due <= 0:
        hold(participant)
        return Response({
            'success': True,
            'paid_with_credit': True,
            'credit_used': str(credit_used),
            'amount_due': '0.00',
            'payment_status': participant.payment_status,
        })

    tx_ref = f"RIVALINK-M{match.id}U{request.user.id}-{uuid.uuid4().hex[:8].upper()}"
    payment = Payment.objects.create(
        user=request.user,
        tx_ref=tx_ref,
        amount=amount_due,
        currency='ETB',
        payment_type='match_share',
        reference_type='match',
        reference_id=match.id,
        description=f'Share for "{match.title}" (credit Br {credit_used})',
    )

    chapa_secret = getattr(settings, 'CHAPA_SECRET_KEY', '')
    if not chapa_secret:
        if settings.DEBUG:
            # Dev fallback so the escrow flow is testable without a gateway.
            payment.status = 'success'
            payment.save(update_fields=['status'])
            hold(participant)
            return Response({'success': True, 'mock': True, 'tx_ref': tx_ref,
                             'credit_used': str(credit_used),
                             'amount_due': str(amount_due),
                             'payment_status': participant.payment_status})
        payment.status = 'failed'
        payment.save(update_fields=['status'])
        _return_credit()
        if request.user.id == match.organizer_id:
            release_reservation(match)
        return Response({'success': False, 'message': 'Payment system not configured'},
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    payload = {
        'amount': str(amount_due),
        'currency': 'ETB',
        'email': request.user.email,
        'tx_ref': tx_ref,
        'callback_url': f'{settings.SITE_URL}/api/payments/webhook/',
        'return_url': request.data.get('return_url', ''),
        'customization': {
            'title': 'Victiqo share',
            'description': f'Match {match.id} share',
        },
    }
    try:
        resp = http_requests.post(
            'https://api.chapa.co/v1/transaction/initialize',
            json=payload,
            headers={'Authorization': f'Bearer {chapa_secret}', 'Content-Type': 'application/json'},
            timeout=30,
        )
        data = resp.json()
        if resp.status_code == 200 and data.get('status') == 'success':
            payment.chapa_tx_id = data.get('data', {}).get('tx_ref', tx_ref)
            payment.save(update_fields=['chapa_tx_id'])
            return Response({'success': True,
                             'checkout_url': data.get('data', {}).get('checkout_url', ''),
                             'credit_used': str(credit_used),
                             'amount_due': str(amount_due),
                             'tx_ref': tx_ref})
        payment.status = 'failed'
        payment.save(update_fields=['status'])
        _return_credit()
        if request.user.id == match.organizer_id:
            release_reservation(match)
        return Response({'success': False, 'message': data.get('message', 'Payment initialization failed')},
                        status=status.HTTP_400_BAD_REQUEST)
    except http_requests.RequestException:
        payment.status = 'failed'
        payment.save(update_fields=['status'])
        _return_credit()
        if request.user.id == match.organizer_id:
            release_reservation(match)
        return Response({'success': False, 'message': 'Payment service unavailable. Try again.'},
                        status=status.HTTP_503_SERVICE_UNAVAILABLE)


# ── Field booking: host requests, every player confirms, then it's booked ──

def _book_field_for_match(match):
    """Book the venue from the match pot; hold any surplus for withdrawals."""
    if MatchPot.objects.filter(match=match).exists():
        return {
            'booking_id': (VenueBooking.objects.filter(match=match).first() or VenueBooking()).id,
            'venue': match.venue.name if match.venue else '',
            'already_booked': True,
            **funding_summary(match),
        }

    try:
        reserve_for_match(match)
    except ValueError as exc:
        raise ValueError(str(exc))

    venue = match.venue
    if venue is None:
        raise ValueError('Attach a venue to this match first')

    local_dt = timezone.localtime(match.date_time)
    end_dt = local_dt + timedelta(hours=BOOKING_SLOT_HOURS)
    slot_price = money(venue.slot_price)

    booking = VenueBooking.objects.filter(match=match).first()
    if booking is None:
        booking = VenueBooking(
            match=match, venue=venue, booked_by=match.organizer,
            date=local_dt.date(), start_time=local_dt.time().replace(second=0, microsecond=0),
            end_time=end_dt.time().replace(second=0, microsecond=0),
            hours=BOOKING_SLOT_HOURS, total_price=slot_price,
        )
    booking.total_price = money(booking.total_price or slot_price)
    booking.status = 'confirmed'
    booking.payment_status = 'paid'
    booking.paid_at = timezone.now()
    booking.save()

    participants = list(active_participants(match))
    collected = money(sum((p.amount_paid or 0) for p in participants))
    fee = money(FIELD_SERVICE_FEE_ETB) if booking.total_price > 0 else money(0)
    target = money(booking.total_price + fee)
    if collected < target:
        shortfall = money(target - collected)
        raise ValueError(
            f'The pot is short by Br {shortfall}. '
            f'Br {target} is needed before the field can be booked.'
        )

    MatchParticipant.objects.filter(
        match=match, withdrawn_at__isnull=True, payment_status='held',
    ).update(payment_status='released')

    pot = MatchPot.objects.create(
        match=match,
        collected=collected,
        venue_amount=booking.total_price,
        platform_fee=fee,
        surplus=money(collected - target),
        status='booked',
    )

    credit_host(
        venue.owner, booking.total_price, 'venue_release', match=match,
        note=f'Venue payment for "{match.title}" ({venue.name})',
    )
    if fee > 0:
        record_transaction(
            'field_service_fee', fee, payer=match.organizer,
            reference_type='match', reference_id=match.id, status='collected',
            note=f'Field booking service fee for "{match.title}"',
        )

    booking.venue.total_bookings += 1
    booking.venue.save(update_fields=['total_bookings'])

    match.booking_status = 'confirmed'
    match.booking_confirmed_at = timezone.now()
    match.save(update_fields=['booking_status', 'booking_confirmed_at'])

    for p in MatchParticipant.objects.filter(match=match).select_related('user'):
        notify(p.user, 'booking_confirmed', 'Field booked',
               f'{venue.name} is booked for "{match.title}". See you there!', match=match)
    notify(
        venue.owner, 'general', 'Venue payment received',
        f'Br {booking.total_price} was added to your earnings for "{match.title}".',
    )

    return {
        'booking_id': booking.id,
        'venue': venue.name,
        'slot_price': str(booking.total_price),
        'pot': funding_summary(match),
        'surplus_held': str(pot.surplus),
        'venue_payable': str(booking.total_price),
    }


@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def request_venue_booking(request, match_id):
    """Host asks every joined player to confirm before the field is booked."""
    try:
        match = Match.objects.get(id=match_id)
    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)

    if match.organizer.id != request.user.id:
        return Response({'error': 'Only the organizer can request the booking'},
                        status=status.HTTP_403_FORBIDDEN)
    if not match.is_active:
        return Response({'error': 'This match is cancelled'}, status=status.HTTP_400_BAD_REQUEST)
    if not match.venue:
        return Response({'error': 'Attach a venue to this match first'},
                        status=status.HTTP_400_BAD_REQUEST)
    if match.booking_status == 'confirmed':
        return Response({'error': 'The field is already booked'}, status=status.HTTP_400_BAD_REQUEST)

    participants = MatchParticipant.objects.filter(match=match, withdrawn_at__isnull=True)
    unpaid = participants.filter(payment_status='unpaid').count()
    if unpaid:
        return Response({
            'error': f'{unpaid} player(s) have not paid their share yet. '
                     'Everyone, including the host, must pay before the field is booked.',
        }, status=status.HTTP_400_BAD_REQUEST)

    active_count = participants.count()
    if active_count < max(1, match.min_players):
        return Response({
            'error': f'Need at least {match.min_players} players before booking '
                     f'(currently {active_count}).',
        }, status=status.HTTP_400_BAD_REQUEST)

    collected = money(sum((p.amount_paid or 0) for p in participants))
    fee = money(FIELD_SERVICE_FEE_ETB) if match.venue.slot_price > 0 else money(0)
    target = money(match.venue.slot_price + fee)
    if collected < target:
        return Response({
            'error': f'Br {target} is needed to book {match.venue.name}. '
                     f'Only Br {collected} has been collected — '
                     f'Br {money(target - collected)} short.',
            'funding': funding_summary(match),
            'upgrade_required': False,
        }, status=status.HTTP_400_BAD_REQUEST)

    match.booking_status = 'requested'
    match.booking_requested_at = timezone.now()
    match.save(update_fields=['booking_status', 'booking_requested_at'])
    participants.update(booking_confirmed=False, booking_confirmed_at=None)

    for p in participants.exclude(user=request.user).select_related('user'):
        notify(
            p.user, 'booking_request', 'Confirm the field booking',
            f'"{match.title}" is about to book {match.venue.name}. '
            f'Confirm to lock it in — after booking your Br {p.amount_paid or match.price} '
            'is non-refundable unless the host or venue cancels.',
            match=match,
        )

    return Response({
        'success': True,
        'booking_status': 'requested',
        'players': active_count,
        'confirmed': 0,
        'funding': funding_summary(match),
        'note': 'Every player must confirm before the field is booked.',
    })


@api_view(['POST'])
def confirm_venue_booking(request, match_id):
    """A player confirms the field booking (accepts the non-refundable share)."""
    try:
        match = Match.objects.get(id=match_id)
    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)

    participant = MatchParticipant.objects.filter(
        match=match, user=request.user, withdrawn_at__isnull=True).first()
    if not participant:
        return Response({'error': 'Only active joined players can confirm'},
                        status=status.HTTP_403_FORBIDDEN)

    if match.booking_status == 'confirmed':
        return Response({'success': True, 'booking_status': 'confirmed',
                         'message': 'Field already booked'})
    if match.booking_status != 'requested':
        return Response({'error': 'The host has not requested a booking yet'},
                        status=status.HTTP_400_BAD_REQUEST)

    participant.booking_confirmed = True
    participant.booking_confirmed_at = timezone.now()
    participant.save(update_fields=['booking_confirmed', 'booking_confirmed_at'])

    if not all_players_confirmed(match):
        total = MatchParticipant.objects.filter(
            match=match, withdrawn_at__isnull=True).exclude(
            user_id=match.organizer_id).count()
        confirmed = MatchParticipant.objects.filter(
            match=match, booking_confirmed=True, withdrawn_at__isnull=True).exclude(
            user_id=match.organizer_id).count()
        return Response({
            'success': True,
            'booking_status': 'requested',
            'confirmed': confirmed,
            'players': total,
            'message': f'Confirmed {confirmed}/{total} — waiting for the rest',
        })

    try:
        booked = _book_field_for_match(match)
    except ValueError as exc:
        return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
    return Response({'success': True, 'booking_status': 'confirmed',
                     'message': 'Everyone confirmed — field booked!', **booked})


@api_view(['GET'])
def get_match_recommendations(request):
    """Get ranked, personalized match recommendations for the user."""
    user = request.user
    if not user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    from .engagement import recommend_matches
    return Response({'recommendations': recommend_matches(user, limit=10)},
                    status=status.HTTP_200_OK)
