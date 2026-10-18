from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.contrib.auth.models import User
from django.db.models import Q
from django.utils import timezone
from django.db import transaction
from datetime import datetime
from .models import (
    UserProfile, Team, Match, MatchParticipant, MatchWaitlist, Notification,
    ChatMessage, PlayerRating, MatchResult, Favorite,
)
from .push import notify
from .entitlements import (
    can_host_match,
)
from .monetization import (
    host_fee_for, record_transaction,
)
from .serializers import (
    err_msg as _err_msg, display_name, match_summary, match_my, match_history,
)
from .validators import (
    SPORT_CHOICES, MATCH_TYPES, RESULT_TYPES, SKILL_LEVELS, validate_string, validate_optional_string,
    validate_int, validate_optional_int, validate_decimal, validate_enum, sanitize_text, validate_date_iso,
)


from .view_shared import (
    _compute_rankings,
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

        messages = ChatMessage.objects.filter(match=match).select_related('user')[:100]

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

        return Response({'message': 'You have left the match'}, status=status.HTTP_200_OK)

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

        # Notify every participant except organizer
        participants = MatchParticipant.objects.filter(match=match).exclude(user=request.user).select_related('user')
        for p in participants:
            notify(
                p.user,
                'match_cancelled',
                'Match cancelled',
                f'"{match.title}" has been cancelled by the organizer.',
                match=match,
            )

        match.is_active = False
        match.save()

        return Response({'message': 'Match cancelled successfully'}, status=status.HTTP_200_OK)

    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Feature 2: Leave Team ──



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

        qs = qs.order_by('-organizer__profile__is_premium', 'date_time')
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
            price = validate_decimal(request.data.get('price', 0), 0, 999999, 'Price')
            skill_level = validate_enum(request.data.get('skill_level', 'any'), SKILL_LEVELS, 'skill_level')
            team_id = request.data.get('team_id')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        team = None
        if team_id:
            team = Team.objects.get(id=team_id)

        if not can_host_match(request.user):
            return Response({
                'error': 'Free accounts can host 2 matches per month. Upgrade to Premium for unlimited hosting.',
                'upgrade_required': True,
            }, status=status.HTTP_402_PAYMENT_REQUIRED)

        match = Match.objects.create(
            title=title,
            sport=sport,
            description=description,
            location=location,
            date_time=date_time,
            max_players=max_players,
            price=price,
            skill_level=skill_level,
            organizer=request.user,
            team=team,
            current_players=1,
        )

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
                'current_players': match.current_players,
                'price': str(match.price),
                'skill_level': match.skill_level,
                'organizer_id': match.organizer.id,
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

        matches = qs.select_related('organizer', 'organizer__profile').order_by(
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

        queryset = Match.objects.select_related('organizer').all()

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

        matches_data = [
            match_my(match, request.user, joined_ids, saved_ids)
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

        is_participant = False
        is_organizer = False
        if request.user and request.user.is_authenticated:
            is_participant = MatchParticipant.objects.filter(
                match=match, user=request.user
            ).exists()
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
            }
            if is_organizer or p.user.id == request.user.id:
                participant_info['email'] = p.user.email
                participant_info['phone'] = phone
            participants_data.append(participant_info)

        organizer_name = display_name(match.organizer)

        return Response({
            'match': {
                'id': match.id,
                'title': match.title,
                'sport': match.sport,
                'description': match.description,
                'location': match.location,
                'date_time': match.date_time.isoformat(),
                'max_players': match.max_players,
                'current_players': match.current_players,
                'spots_left': match.max_players - match.current_players,
                'price': str(match.price),
                'skill_level': match.skill_level,
                'organizer_id': match.organizer.id,
                'organizer_name': organizer_name,
                'is_organizer': is_organizer,
                'is_participant': is_participant,
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
        comment = request.data.get('comment', '')

        if not rated_user_id or not rating:
            return Response({'error': 'rated_user_id and rating are required'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            rated_user = User.objects.get(id=rated_user_id)
        except User.DoesNotExist:
            return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

        if int(rating) < 1 or int(rating) > 5:
            return Response({'error': 'Rating must be between 1 and 5'}, status=status.HTTP_400_BAD_REQUEST)

        is_participant = MatchParticipant.objects.filter(match=match, user=rater).exists()
        if not is_participant:
            return Response({'error': 'You must be a participant to rate others'}, status=status.HTTP_403_FORBIDDEN)

        rating_obj, created = PlayerRating.objects.update_or_create(
            match=match,
            rater=rater,
            rated_user=rated_user,
            defaults={'rating': rating, 'comment': comment}
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




@api_view(['GET', 'POST', 'PUT'])
@permission_classes([AllowAny])
def match_result(request, match_id):
    """Get or submit match result"""
    try:
        match = Match.objects.get(id=match_id)
    except Match.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)

    if request.method == 'GET':
        try:
            result = MatchResult.objects.get(match=match)
            return Response({
                'result': {
                    'id': result.id,
                    'match_id': match.id,
                    'match_type': result.match_type,
                    'result_type': result.result_type,
                    'winner_team_id': result.winner_team_id,
                    'winner_user_id': result.winner_user_id,
                    'mvp_user_id': result.mvp_user_id,
                    'score': result.score,
                    'notes': result.notes,
                    'created_by': result.created_by.username if result.created_by else None,
                    'created_at': result.created_at.isoformat(),
                }
            }, status=status.HTTP_200_OK)
        except MatchResult.DoesNotExist:
            return Response({'result': None}, status=status.HTTP_200_OK)

    elif request.method in ['POST', 'PUT']:
        user = request.user
        if not user.is_authenticated:
            return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

        if match.organizer.id != user.id:
            return Response({'error': 'Only the match organizer can set results'}, status=status.HTTP_403_FORBIDDEN)

        try:
            match_type = validate_enum(request.data.get('match_type', 'pickup'), MATCH_TYPES, 'match_type')
            result_type = validate_enum(request.data.get('result_type', 'individual'), RESULT_TYPES, 'result_type')
            winner_team_id = validate_optional_int(request.data.get('winner_team_id'), 1, 999999, 'winner_team_id')
            winner_user_id = validate_optional_int(request.data.get('winner_user_id'), 1, 999999, 'winner_user_id')
            winning_group = validate_optional_string(request.data.get('winning_group', ''), 10, 'winning_group')
            mvp_user_id = validate_optional_int(request.data.get('mvp_user_id'), 1, 999999, 'mvp_user_id')
            score = validate_optional_string(request.data.get('score', ''), 50, 'score')
            notes = validate_optional_string(request.data.get('notes', ''), 5000, 'notes')
            team_groups = request.data.get('team_groups')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        participant_ids = set(MatchParticipant.objects.filter(match=match).values_list('user_id', flat=True))

        if match_type == 'team_vs_team' and result_type != 'draw' and not winner_team_id:
            return Response({'error': 'winner_team_id is required for team vs team matches'}, status=status.HTTP_400_BAD_REQUEST)

        if result_type != 'draw':
            if match_type == 'pickup' and not winner_user_id:
                return Response({'error': 'winner_user_id is required for non-draw pickup matches'}, status=status.HTTP_400_BAD_REQUEST)
            if match_type == 'pickup' and winner_user_id and winner_user_id not in participant_ids:
                return Response({'error': 'winner_user_id is not a participant of this match'}, status=status.HTTP_400_BAD_REQUEST)

        if mvp_user_id and mvp_user_id not in participant_ids:
            return Response({'error': 'mvp_user_id is not a participant of this match'}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            result, created = MatchResult.objects.update_or_create(
                match=match,
                defaults={
                    'match_type': match_type,
                    'result_type': result_type,
                    'winner_team_id': winner_team_id,
                    'winner_user_id': winner_user_id,
                    'winning_group': winning_group,
                    'mvp_user_id': mvp_user_id,
                    'score': score,
                    'notes': notes,
                    'created_by': user,
                }
            )

            if team_groups and isinstance(team_groups, dict):
                for group, user_ids in team_groups.items():
                    if group not in ('A', 'B'):
                        continue
                    for uid in user_ids:
                        MatchParticipant.objects.filter(match=match, user_id=uid).update(team_group=group)

            _compute_rankings(match, result)

        return Response({
            'message': 'Match result saved successfully',
            'result': {
                'id': result.id,
                'match_id': match.id,
                'match_type': result.match_type,
                'result_type': result.result_type,
                'winner_team_id': result.winner_team_id,
                'winner_user_id': result.winner_user_id,
                'winning_group': result.winning_group,
                'mvp_user_id': result.mvp_user_id,
                'score': result.score,
                'notes': result.notes,
            }
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)




@api_view(['GET'])
def get_match_recommendations(request):
    """Get recommended matches for the user"""
    user = request.user
    if not user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    user_sports = []
    try:
        profile = user.profile
        if profile.favorite_sports:
            user_sports = [s.strip() for s in profile.favorite_sports.split(',')]
    except UserProfile.DoesNotExist:
        pass

    user_participated_matches = MatchParticipant.objects.filter(user=user).values_list('match_id', flat=True)
    
    recommended = Match.objects.filter(
        date_time__gte=timezone.now(),
        is_active=True
    ).exclude(
        id__in=user_participated_matches
    ).exclude(
        organizer=user
    ).select_related('organizer', 'organizer__profile')

    if user_sports:
        recommended = recommended.filter(sport__in=user_sports)
    
    recommended = recommended.order_by(
        '-organizer__profile__is_premium', 'date_time')[:10]

    matches_data = [match_summary(match) for match in recommended]

    return Response({'recommendations': matches_data}, status=status.HTTP_200_OK)
