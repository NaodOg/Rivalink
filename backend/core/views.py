from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.authtoken.models import Token
from django.contrib.auth.models import User
from django.contrib.auth import authenticate
from django.db import IntegrityError
from django.db.models import Q, Count
from django.conf import settings
from django.utils import timezone
from django.db import transaction
from datetime import datetime, timedelta, time
import random
from .models import UserProfile, Team, TeamMember, Match, MatchParticipant, MatchWaitlist, Notification, ChatMessage, TeamJoinRequest, League, LeagueMember, PlayerRating, MatchResult, Favorite, DirectMessage, Referee, RefereeBooking, RefereeRating, Venue, VenueBooking, VenueRating, Tournament, TournamentTeam, TournamentMatch, UserSportRating, TeamRanking, Report, Block, DeviceToken, Follow, Referral
from .elo import update_elo_with_matches
from .push import notify, send_push, push_many
from .sms import send_sms
from .entitlements import (
    is_premium, can_host_match, can_create_team, can_join_team, team_all_premium,
)
from .serializers import (
    err_msg as _err_msg, display_name,
    match_summary, match_my, match_history,
    league_summary, league_standing,
    referee_to_dict as _referee_to_dict, booking_to_dict as _booking_to_dict,
    venue_to_dict as _venue_to_dict, venue_booking_to_dict as _venue_booking_to_dict,
    tournament_to_dict as _tournament_to_dict,
    tournament_team_to_dict as _tournament_team_to_dict,
    tournament_match_to_dict as _tournament_match_to_dict,
)
from .validators import (
    AuthRateThrottle, CreateRateThrottle, SensitiveWriteThrottle,
    SPORT_CHOICES, TOURNAMENT_FORMATS, MATCH_TYPES, RESULT_TYPES,
    SKILL_LEVELS, REPORT_CATEGORIES,
    validate_email, validate_phone, validate_string, validate_optional_string,
    validate_int, validate_optional_int, validate_decimal, validate_enum,
    sanitize_text, validate_password, validate_image, validate_date_iso,
    validate_boolean, validate_favorite_type,
)

@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    return Response({
        "status": "ok",
        "message": "VYRO backend connected successfully"
    })

@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def signup(request):
    """
    User registration endpoint
    Expected data: name, phone, email, password
    """
    try:
        try:
            name = validate_string(request.data.get('name'), 100, 'Name')
            phone = validate_phone(request.data.get('phone'))
            email = validate_email(request.data.get('email'))
            password = validate_password(request.data.get('password'))
            location = validate_optional_string(request.data.get('location', ''), 200, 'Location')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if user already exists
        if User.objects.filter(username=email).exists():
            return Response(
                {'error': 'User with this email already exists'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Create user
        user = User.objects.create_user(
            username=email,
            email=email,
            password=password,
            first_name=name.split()[0] if name else '',
            last_name=' '.join(name.split()[1:]) if len(name.split()) > 1 else ''
        )
        
        # Create user profile with phone and location
        UserProfile.objects.create(user=user, phone=phone, location=location)
        UserProfile.get_or_create_for_user(user)  # ensure a referral code exists

        # Referral code redemption
        ref_code = (request.data.get('referral_code') or '').strip().upper()
        if ref_code:
            referrer_profile = UserProfile.objects.filter(
                referral_code=ref_code).select_related('user').first()
            if referrer_profile and referrer_profile.user_id != user.id:
                Referral.objects.create(
                    referrer=referrer_profile.user, referred=user, code=ref_code, credit=50)
                referrer_profile.referral_credit += 50
                referrer_profile.save(update_fields=['referral_credit'])
                my_profile = UserProfile.get_or_create_for_user(user)
                my_profile.referral_credit += 25
                my_profile.save(update_fields=['referral_credit'])
        
        # Create token
        token, created = Token.objects.get_or_create(user=user)
        
        return Response({
            'message': 'Account created successfully',
            'token': token.key,
            'user': {
                'id': user.id,
                'name': name,
                'phone': phone,
                'email': user.email,
                'profile_image': None,
                'bio': '',
                'location': location,
                'favorite_sports': [],
                'is_premium': False,
            }
        }, status=status.HTTP_201_CREATED)
        
    except IntegrityError:
        return Response(
            {'error': 'User with this email already exists'},
            status=status.HTTP_400_BAD_REQUEST
        )
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


# ── Leagues ──

@api_view(['GET'])
@permission_classes([AllowAny])
def get_leagues(request):
    """
    Get all active leagues (discover)
    """
    try:
        leagues = League.objects.filter(
            is_active=True,
            start_date__gte=timezone.now()
        ).select_related('organizer').order_by('start_date')[:20]

        data = [league_summary(league) for league in leagues]

        return Response({'leagues': data}, status=status.HTTP_200_OK)

    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
def get_my_leagues(request):
    """
    Get leagues the user's teams are in
    """
    try:
        # Get teams the user owns
        owned_teams = Team.objects.filter(owner=request.user)
        
        # Get league memberships for those teams
        memberships = LeagueMember.objects.filter(
            team__in=owned_teams
        ).select_related('league', 'team')

        data = []
        for m in memberships:
            league = m.league
            data.append({
                'league_id': league.id,
                'league_name': league.name,
                'sport': league.sport,
                'format': league.format,
                'team_id': m.team.id,
                'team_name': m.team.name,
                'wins': m.wins,
                'losses': m.losses,
                'points': m.points,
                'win_rate': round(m.win_rate, 1),
                'start_date': league.start_date.isoformat(),
            })

        return Response({'leagues': data}, status=status.HTTP_200_OK)

    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def create_league(request):
    """
    Create a new league
    """
    try:
        try:
            name = validate_string(request.data.get('name'), 100, 'League name')
            sport = validate_enum(request.data.get('sport', 'other'), SPORT_CHOICES, 'Sport')
            league_format = validate_optional_string(request.data.get('format', '5v5'), 50, 'Format')
            max_teams = validate_int(request.data.get('max_teams', 8), 2, 256, 'Max teams')
            entry_fee = validate_decimal(request.data.get('entry_fee', 0), 0, 999999, 'Entry fee')
            prize = validate_optional_string(request.data.get('prize', ''), 2000, 'Prize')
            location = validate_optional_string(request.data.get('location', ''), 200, 'Location')
            start_dt = validate_date_iso(request.data.get('start_date'), 'Start date')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        if not is_premium(request.user):
            return Response({
                'error': 'Only Premium users can create leagues.',
                'upgrade_required': True,
            }, status=status.HTTP_402_PAYMENT_REQUIRED)

        league = League.objects.create(
            name=name,
            sport=sport,
            format=league_format,
            max_teams=max_teams,
            entry_fee=entry_fee,
            prize=prize,
            location=location,
            start_date=start_dt,
            organizer=request.user,
        )

        return Response({
            'message': 'League created successfully',
            'league': {
                'id': league.id,
                'name': league.name,
            }
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['PUT'])
@throttle_classes([SensitiveWriteThrottle])
def edit_league(request, league_id):
    try:
        league = League.objects.get(id=league_id, organizer=request.user)
        try:
            if 'name' in request.data:
                league.name = validate_string(request.data['name'], 100, 'League name')
            if 'sport' in request.data:
                league.sport = validate_enum(request.data['sport'], SPORT_CHOICES, 'Sport')
            if 'format' in request.data:
                league.format = validate_optional_string(request.data['format'], 50, 'Format')
            if 'max_teams' in request.data:
                league.max_teams = validate_int(request.data['max_teams'], 2, 256, 'Max teams')
            if 'entry_fee' in request.data:
                league.entry_fee = validate_decimal(request.data['entry_fee'], 0, 999999, 'Entry fee')
            if 'prize' in request.data:
                league.prize = validate_optional_string(request.data['prize'], 2000, 'Prize')
            if 'location' in request.data:
                league.location = validate_optional_string(request.data['location'], 200, 'Location')
            if 'start_date' in request.data:
                league.start_date = validate_date_iso(request.data['start_date'], 'Start date')
            if 'is_active' in request.data:
                league.is_active = validate_boolean(request.data['is_active'], 'Is active')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        league.save()
        return Response({'success': True, 'message': 'League updated successfully', 'league': {'id': league.id, 'name': league.name}})

    except League.DoesNotExist:
        return Response({'error': 'League not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['DELETE'])
@throttle_classes([SensitiveWriteThrottle])
def delete_league(request, league_id):
    try:
        league = League.objects.get(id=league_id, organizer=request.user)
        league.delete()
        return Response({'success': True, 'message': 'League deleted successfully'})
    except League.DoesNotExist:
        return Response({'error': 'League not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def join_league(request):
    """
    Join a league with a team
    """
    try:
        league_id = request.data.get('league_id')
        team_id = request.data.get('team_id')

        if not league_id or not team_id:
            return Response({'error': 'League ID and Team ID are required'}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            league = League.objects.select_for_update().get(id=league_id)
            team = Team.objects.get(id=team_id)

            if team.owner.id != request.user.id:
                return Response({'error': 'Only the team owner can join a league'}, status=status.HTTP_403_FORBIDDEN)

            if not is_premium(request.user):
                return Response({
                    'error': 'Only Premium users can join leagues.',
                    'upgrade_required': True,
                }, status=status.HTTP_402_PAYMENT_REQUIRED)

            if not team_all_premium(team):
                return Response({
                    'error': 'All team members need VYRO Premium to join a league.',
                    'upgrade_required': True,
                }, status=status.HTTP_402_PAYMENT_REQUIRED)

            if league.current_teams >= league.max_teams:
                return Response({'error': 'League is full'}, status=status.HTTP_400_BAD_REQUEST)

            existing = LeagueMember.objects.filter(league=league, team=team).first()
            if existing:
                return Response({'error': 'Team already in this league'}, status=status.HTTP_400_BAD_REQUEST)

            LeagueMember.objects.create(
                league=league,
                team=team,
                role='member'
            )

            league.current_teams += 1
            league.save()

        return Response({'message': 'Team joined league successfully'}, status=status.HTTP_201_CREATED)

    except League.DoesNotExist:
        return Response({'error': 'League not found'}, status=status.HTTP_404_NOT_FOUND)
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@permission_classes([AllowAny])
def get_league_details(request, league_id):
    """
    Get league details and standings
    """
    try:
        league = League.objects.select_related('organizer').get(id=league_id)

        members = LeagueMember.objects.filter(league=league).select_related('team')
        members = sorted(members, key=lambda m: (-m.points, -m.goal_difference, -m.goals_for))

        standings = [league_standing(m, i + 1) for i, m in enumerate(members)]

        return Response({
            'league': league_summary(league),
            'standings': standings,
        }, status=status.HTTP_200_OK)

    except League.DoesNotExist:
        return Response({'error': 'League not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Edit Match ──

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

@api_view(['GET'])
def get_team_chat(request, team_id):
    """
    Get chat messages for a team. Only team members can view.
    """
    try:
        team = Team.objects.get(id=team_id)

        is_member = TeamMember.objects.filter(team=team, user=request.user).exists()
        is_owner = team.owner.id == request.user.id

        if not is_member and not is_owner:
            return Response(
                {'error': 'You are not a member of this team'},
                status=status.HTTP_403_FORBIDDEN
            )

        messages = ChatMessage.objects.filter(team=team).select_related('user')[:100]

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

    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def send_team_chat(request, team_id):
    """
    Send a chat message to a team. Only team members can send.
    """
    try:
        team = Team.objects.get(id=team_id)
        try:
            raw_message = request.data.get('message', '')
            message_text = sanitize_text(validate_string(raw_message, 10000, 'Message'))
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        is_member = TeamMember.objects.filter(team=team, user=request.user).exists()
        is_owner = team.owner.id == request.user.id

        if not is_member and not is_owner:
            return Response(
                {'error': 'You are not a member of this team'},
                status=status.HTTP_403_FORBIDDEN
            )

        chat_message = ChatMessage.objects.create(
            team=team,
            user=request.user,
            message=message_text
        )

        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username

        # Notify all other team members (single bulk insert)
        other_members = TeamMember.objects.filter(team=team).exclude(user=request.user).values_list('user_id', flat=True)
        notified = set(other_members)
        if team.owner.id != request.user.id:
            notified.add(team.owner.id)
        Notification.objects.bulk_create([
            Notification(
                user_id=uid,
                notification_type='team_chat_message',
                title=f'New message in {team.name}',
                message=f'{user_name}: {message_text[:100]}',
                related_team=team,
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

    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def login(request):
    """
    User login endpoint
    Expected data: email, password
    """
    try:
        try:
            email = validate_email(request.data.get('email'))
            password = request.data.get('password')
            if not password:
                return Response({'error': 'Password is required'}, status=status.HTTP_400_BAD_REQUEST)
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        # Authenticate user
        user = authenticate(username=email, password=password)
        
        if user is None:
            return Response(
                {'error': 'Invalid email or password'},
                status=status.HTTP_401_UNAUTHORIZED
            )
        
        # Get or create token
        token, created = Token.objects.get_or_create(user=user)
        
        # Get full name
        full_name = f"{user.first_name} {user.last_name}".strip()
        if not full_name:
            full_name = user.username
        
        # Get profile fields
        phone = ''
        bio = ''
        location = ''
        fav_sports = ''
        profile_image = None
        if hasattr(user, 'profile'):
            phone = user.profile.phone
            bio = user.profile.bio
            location = user.profile.location
            fav_sports = user.profile.favorite_sports
            profile_image = user.profile.profile_image
        
        return Response({
            'message': 'Login successful',
            'token': token.key,
            'user': {
                'id': user.id,
                'name': full_name,
                'phone': phone,
                'email': user.email,
                'profile_image': profile_image,
                'bio': bio or '',
                'location': location or '',
                'favorite_sports': fav_sports.split(',') if fav_sports else [],
                'is_premium': user.profile.premium_active if hasattr(user, 'profile') else False,
            }
        }, status=status.HTTP_200_OK)
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


@api_view(['POST'])
def upload_profile_image(request):
    if not request.user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)
    uploaded = request.FILES.get('image')
    if not uploaded:
        return Response({'error': 'No image provided'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        try:
            validate_image(uploaded)
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        import uuid, os
        from django.core.files.storage import default_storage
        ext = uploaded.name.rsplit('.', 1)[-1] if '.' in uploaded.name else 'jpg'
        filename = f'profiles/{uuid.uuid4().hex}.{ext}'
        saved = default_storage.save(filename, uploaded)
        url = f'{settings.MEDIA_URL}{saved}'
        profile = UserProfile.get_or_create_for_user(request.user)
        profile.profile_image = url
        profile.save(update_fields=['profile_image'])
        return Response({'url': url}, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

def _user_payload(user):
    phone = ''
    bio = ''
    location = ''
    fav_sports = ''
    profile_image = None
    if hasattr(user, 'profile'):
        phone = user.profile.phone
        bio = user.profile.bio
        location = user.profile.location
        fav_sports = user.profile.favorite_sports
        profile_image = user.profile.profile_image
    full_name = f"{user.first_name} {user.last_name}".strip() or user.username
    return {
        'id': user.id,
        'name': full_name,
        'phone': phone,
        'email': user.email,
        'profile_image': profile_image,
        'bio': bio or '',
        'location': location or '',
        'favorite_sports': fav_sports.split(',') if fav_sports else [],
        'is_premium': user.profile.premium_active if hasattr(user, 'profile') else False,
    }


@api_view(['GET', 'PATCH'])
def update_profile(request):
    """
    Get or update the current user's profile.
    PATCH expected data: name, email, profile_image, bio, location, favorite_sports (optional)
    """
    if not request.user.is_authenticated:
        return Response(
            {'error': 'Authentication required'},
            status=status.HTTP_401_UNAUTHORIZED
        )

    if request.method == 'GET':
        return Response({'user': _user_payload(request.user)})

    try:
        user = request.user
        try:
            if 'name' in request.data and request.data['name']:
                validate_string(request.data['name'], 100, 'Name')
            if 'email' in request.data and request.data['email']:
                validate_email(request.data['email'])
            if 'bio' in request.data:
                request.data['bio'] = sanitize_text(str(request.data['bio'])[:1000])
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        name = request.data.get('name')
        email = request.data.get('email')
        profile_image = request.data.get('profile_image')
        bio = request.data.get('bio')
        location = request.data.get('location')
        favorite_sports = request.data.get('favorite_sports')
        
        # Update user fields
        if name:
            name_parts = str(name).split()
            user.first_name = name_parts[0] if name_parts else ''
            user.last_name = ' '.join(name_parts[1:]) if len(name_parts) > 1 else ''
        
        if email and email != user.email:
            if User.objects.exclude(pk=user.pk).filter(email=email).exists():
                return Response(
                    {'error': 'Email already in use'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            user.email = email
        
        user.save()
        
        # Update profile fields
        if hasattr(user, 'profile'):
            if profile_image is not None:
                user.profile.profile_image = profile_image
            if bio is not None:
                user.profile.bio = bio
            if location is not None:
                user.profile.location = location
            if favorite_sports is not None:
                user.profile.favorite_sports = favorite_sports
            user.profile.save()
        
        # Get phone from profile
        phone = ''
        bio = ''
        location = ''
        fav_sports = ''
        if hasattr(user, 'profile'):
            phone = user.profile.phone
            bio = user.profile.bio
            location = user.profile.location
            fav_sports = user.profile.favorite_sports
        
        full_name = f"{user.first_name} {user.last_name}".strip()
        if not full_name:
            full_name = user.username

        return Response({
            'message': 'Profile updated successfully',
            'user': _user_payload(user),
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


# ── Feature 1: Leave / Cancel Match ──

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

@api_view(['POST'])
def leave_team(request):
    """
    Leave a team (non-owner only)
    Expected data: team_id
    """
    try:
        team_id = request.data.get('team_id')
        if not team_id:
            return Response({'error': 'Team ID is required'}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            team = Team.objects.select_for_update().get(id=team_id)

            if team.owner.id == request.user.id:
                return Response({'error': 'Team owner cannot leave. Delete the team instead.'}, status=status.HTTP_400_BAD_REQUEST)

            membership = TeamMember.objects.filter(team=team, user=request.user).first()
            if not membership:
                return Response({'error': 'You are not a member of this team'}, status=status.HTTP_400_BAD_REQUEST)

            membership.delete()

            # Update spots left
            team.spots_left = team.max_members - team.current_members
            team.save()

        # Notify team owner
        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        Notification.objects.create(
            user=team.owner,
            notification_type='team_left',
            title='Member Left',
            message=f'{user_name} left your team "{team.name}".',
            related_team=team,
        )

        return Response({'message': 'You have left the team'}, status=status.HTTP_200_OK)

    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Team Management ──

def _is_team_admin_or_owner(team, user):
    if team.owner.id == user.id:
        return True
    return TeamMember.objects.filter(team=team, user=user, role='admin').exists()


@api_view(['GET'])
def get_team_members(request, team_id):
    """
    Get all members of a team. Only for team owner/admin.
    """
    try:
        team = Team.objects.get(id=team_id)
        
        # Check if user is owner or admin
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can view members'}, status=status.HTTP_403_FORBIDDEN)
        
        members = TeamMember.objects.filter(team=team).select_related('user')
        
        data = []
        for m in members:
            user_name = f"{m.user.first_name} {m.user.last_name}".strip() or m.user.username
            member_info = {
                'id': m.id,
                'user_id': m.user.id,
                'user_name': user_name,
                'role': m.role,
                'joined_at': m.joined_at.isoformat(),
            }
            if request.user.id == m.user.id:
                member_info['email'] = m.user.email
            data.append(member_info)
        
        return Response({'members': data}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def remove_team_member(request):
    """
    Remove a member from team. Only for team owner.
    Expected: team_id, member_id
    """
    try:
        team_id = request.data.get('team_id')
        member_id = request.data.get('member_id')
        
        if not team_id or not member_id:
            return Response({'error': 'Team ID and Member ID are required'}, status=status.HTTP_400_BAD_REQUEST)
        
        team = Team.objects.get(id=team_id)
        
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can remove members'}, status=status.HTTP_403_FORBIDDEN)
        
        membership = TeamMember.objects.filter(id=member_id, team=team).first()
        if not membership:
            return Response({'error': 'Member not found'}, status=status.HTTP_404_NOT_FOUND)
        
        if membership.user.id == team.owner.id:
            return Response({'error': 'Cannot remove the owner'}, status=status.HTTP_400_BAD_REQUEST)
        
        member_name = f"{membership.user.first_name} {membership.user.last_name}".strip() or membership.user.username
        membership.delete()
        
        # Update spots left
        team.spots_left = team.max_members - team.current_members
        team.save()
        
        return Response({'message': f'{member_name} removed from team'}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def update_member_role(request):
    """
    Update member role (promote/demote). Only for team owner.
    Expected: team_id, member_id, role (owner/admin/member)
    """
    try:
        team_id = request.data.get('team_id')
        member_id = request.data.get('member_id')
        new_role = request.data.get('role')
        
        if not team_id or not member_id or not new_role:
            return Response({'error': 'Team ID, Member ID, and Role are required'}, status=status.HTTP_400_BAD_REQUEST)
        
        if new_role not in ['admin', 'member']:
            return Response({'error': 'Role must be admin or member'}, status=status.HTTP_400_BAD_REQUEST)
        
        team = Team.objects.get(id=team_id)
        
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can change roles'}, status=status.HTTP_403_FORBIDDEN)
        
        membership = TeamMember.objects.filter(id=member_id, team=team).first()
        if not membership:
            return Response({'error': 'Member not found'}, status=status.HTTP_404_NOT_FOUND)
        
        membership.role = new_role
        membership.save()
        
        return Response({'message': f'Role updated to {new_role}'}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Team Join Requests ──

@api_view(['GET'])
def get_team_join_requests(request, team_id):
    """
    Get pending join requests for a team. Only for team owner.
    """
    try:
        team = Team.objects.get(id=team_id)
        
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can view requests'}, status=status.HTTP_403_FORBIDDEN)
        
        requests = TeamJoinRequest.objects.filter(team=team, status='pending').select_related('user')
        
        data = []
        for req in requests:
            user_name = f"{req.user.first_name} {req.user.last_name}".strip() or req.user.username
            data.append({
                'id': req.id,
                'user_id': req.user.id,
                'user_name': user_name,
                'email': req.user.email,
                'requested_at': req.created_at.isoformat(),
            })
        
        return Response({'requests': data}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def handle_join_request(request):
    """
    Approve or reject a join request. Only for team owner.
    Expected: team_id, request_id, action (approve/reject)
    """
    try:
        team_id = request.data.get('team_id')
        request_id = request.data.get('request_id')
        action = request.data.get('action')
        
        if not team_id or not request_id or not action:
            return Response({'error': 'Team ID, Request ID, and Action are required'}, status=status.HTTP_400_BAD_REQUEST)
        
        if action not in ['approve', 'reject']:
            return Response({'error': 'Action must be approve or reject'}, status=status.HTTP_400_BAD_REQUEST)
        
        team = Team.objects.get(id=team_id)
        
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can handle requests'}, status=status.HTTP_403_FORBIDDEN)
        
        join_request = TeamJoinRequest.objects.filter(id=request_id, team=team).first()
        if not join_request:
            return Response({'error': 'Request not found'}, status=status.HTTP_404_NOT_FOUND)
        
        if action == 'approve':
            if TeamMember.objects.filter(team=team, user=join_request.user).exists():
                return Response({'error': 'User is already a team member'}, status=status.HTTP_400_BAD_REQUEST)
            if team.spots_left <= 0:
                return Response({'error': 'This team is full'}, status=status.HTTP_400_BAD_REQUEST)

            # Add user as team member
            TeamMember.objects.create(
                team=team,
                user=join_request.user,
                role='member'
            )
            join_request.status = 'approved'
            join_request.save()

            # Recompute spots from the source of truth
            team.spots_left = max(0, team.max_members - team.current_members)
            team.save()
            
            # Notify user
            Notification.objects.create(
                user=join_request.user,
                notification_type='team_joined',
                title='Request Approved',
                message=f'Your request to join "{team.name}" has been approved!',
                related_team=team,
            )
            
            return Response({'message': 'Request approved, user added to team'}, status=status.HTTP_200_OK)
        else:
            join_request.status = 'rejected'
            join_request.save()
            
            Notification.objects.create(
                user=join_request.user,
                notification_type='general',
                title='Request Rejected',
                message=f'Your request to join "{team.name}" was rejected.',
                related_team=team,
            )
            
            return Response({'message': 'Request rejected'}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def request_to_join_team(request):
    """
    Request to join a team (instead of instant join)
    """
    try:
        team_id = request.data.get('team_id')
        
        if not team_id:
            return Response({'error': 'Team ID is required'}, status=status.HTTP_400_BAD_REQUEST)
        
        team = Team.objects.get(id=team_id)
        
        # Check if already a member
        existing = TeamMember.objects.filter(team=team, user=request.user).first()
        if existing:
            return Response({'error': 'You are already a member of this team'}, status=status.HTTP_400_BAD_REQUEST)

        if not can_join_team(request.user):
            return Response({
                'error': 'Free accounts can join 1 team. Upgrade to Premium to join more.',
                'upgrade_required': True,
            }, status=status.HTTP_402_PAYMENT_REQUIRED)

        # Check if already requested
        existing_request = TeamJoinRequest.objects.filter(team=team, user=request.user, status='pending').first()
        if existing_request:
            return Response({'error': 'You already have a pending request'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Create request
        TeamJoinRequest.objects.create(
            team=team,
            user=request.user,
            status='pending'
        )
        
        # Notify owner
        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        Notification.objects.create(
            user=team.owner,
            notification_type='general',
            title='New Join Request',
            message=f'{user_name} requested to join your team "{team.name}".',
            related_team=team,
        )
        
        return Response({'message': 'Join request sent'}, status=status.HTTP_201_CREATED)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Feature 3: Match History ──

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
def get_notifications(request):
    """
    Get notifications for the logged-in user
    """
    try:
        notifications = Notification.objects.filter(user=request.user)[:50]

        data = []
        for n in notifications:
            data.append({
                'id': n.id,
                'type': n.notification_type,
                'title': n.title,
                'message': n.message,
                'is_read': n.is_read,
                'created_at': n.created_at.isoformat(),
                'related_match_id': n.related_match_id,
                'related_team_id': n.related_team_id,
            })

        unread_count = Notification.objects.filter(user=request.user, is_read=False).count()

        return Response({
            'notifications': data,
            'unread_count': unread_count,
        }, status=status.HTTP_200_OK)

    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def mark_notifications_read(request):
    """
    Mark notifications as read.
    Optional data: notification_ids (list). If empty, marks ALL as read.
    """
    try:
        ids = request.data.get('notification_ids')
        qs = Notification.objects.filter(user=request.user, is_read=False)
        if ids:
            qs = qs.filter(id__in=ids)
        updated = qs.update(is_read=True)

        return Response({'message': f'{updated} notifications marked as read'}, status=status.HTTP_200_OK)

    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Feature 5: Search / Filter Matches ──

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
def logout(request):
    """
    User logout endpoint - deletes the auth token
    """
    try:
        # Delete the user's token
        request.user.auth_token.delete()
        return Response(
            {'message': 'Logged out successfully'},
            status=status.HTTP_200_OK
        )
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


# Team Endpoints

@api_view(['POST'])
def create_team(request):
    """
    Create a new team
    Expected data: name, sport, description, location, max_members, is_seeking_players
    """
    try:
        try:
            name = validate_string(request.data.get('name'), 100, 'Team name')
            sport = validate_enum(request.data.get('sport', 'other'), SPORT_CHOICES, 'Sport')
            description = sanitize_text(validate_optional_string(request.data.get('description', ''), 5000, 'Description'))
            location = validate_optional_string(request.data.get('location', ''), 200, 'Location')
            max_members = validate_int(request.data.get('max_members', 10), 2, 100, 'Max members')
            is_seeking_players = validate_boolean(request.data.get('is_seeking_players', False), 'is_seeking_players')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        if not can_create_team(request.user):
            return Response({
                'error': 'Free accounts can create 1 team. Upgrade to Premium for unlimited teams.',
                'upgrade_required': True,
            }, status=status.HTTP_402_PAYMENT_REQUIRED)

        team = Team.objects.create(
            name=name,
            sport=sport,
            owner=request.user,
            description=description,
            location=location,
            max_members=max_members,
            is_seeking_players=is_seeking_players,
            spots_left=max_members - 1  # Owner is already a member
        )

        # Add owner as member
        TeamMember.objects.create(
            team=team,
            user=request.user,
            role='owner'
        )

        return Response({
            'message': 'Team created successfully',
            'team': {
                'id': team.id,
                'name': team.name,
                'sport': team.sport,
                'description': team.description,
                'location': team.location,
                'max_members': team.max_members,
                'current_members': team.current_members,
                'is_active': team.is_active,
                'is_seeking_players': team.is_seeking_players,
                'spots_left': team.spots_left,
                'owner_id': team.owner.id,
            }
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


@api_view(['GET'])
def get_my_teams(request):
    """
    Get all teams the user belongs to
    """
    try:
        memberships = TeamMember.objects.filter(user=request.user).select_related('team', 'team__owner').annotate(
            member_count=Count('team__members')
        )
        
        teams = []
        for membership in memberships:
            team = membership.team
            teams.append({
                'id': team.id,
                'name': team.name,
                'sport': team.sport,
                'type': f"{team.sport.title()} {team.max_members}v{team.max_members}",
                'location': team.location,
                'max_members': team.max_members,
                'current_members': membership.member_count,
                'owner_id': team.owner.id,
                'is_active': team.is_active,
                'status': 'Active' if team.is_active else 'Inactive',
                'is_owner': team.owner.id == request.user.id,
                'role': membership.role,
            })

        return Response({
            'teams': teams
        }, status=status.HTTP_200_OK)

    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


@api_view(['GET'])
@permission_classes([AllowAny])
def get_teams_seeking_players(request):
    """
    Get all teams that are seeking players
    """
    try:
        teams = Team.objects.filter(
            is_seeking_players=True,
            is_active=True
        ).select_related('owner').annotate(member_count=Count('members'))

        teams_data = []
        for team in teams:
            teams_data.append({
                'id': team.id,
                'name': team.name,
                'sport': team.sport,
                'type': f"{team.sport.title()} {team.max_members}v{team.max_members}",
                'location': team.location,
                'max_members': team.max_members,
                'current_members': team.member_count,
                'spots_left': team.spots_left,
                'owner_id': team.owner.id,
            })

        return Response({
            'teams': teams_data
        }, status=status.HTTP_200_OK)

    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


@api_view(['POST'])
def join_team(request):
    """
    Join a team
    Expected data: team_id
    """
    try:
        team_id = request.data.get('team_id')
        
        if not team_id:
            return Response(
                {'error': 'Team ID is required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        with transaction.atomic():
            team = Team.objects.select_for_update().get(id=team_id)
            
            # Check if already a member
            if TeamMember.objects.filter(team=team, user=request.user).exists():
                return Response(
                    {'error': 'You are already a member of this team'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if not can_join_team(request.user):
                return Response({
                    'error': 'Free accounts can join 1 team. Upgrade to Premium to join more.',
                    'upgrade_required': True,
                }, status=status.HTTP_402_PAYMENT_REQUIRED)

            # Check if spots available (atomic)
            if team.spots_left <= 0:
                return Response(
                    {'error': 'This team is full'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Add user as member
            TeamMember.objects.create(
                team=team,
                user=request.user,
                role='member'
            )

            # Update spots left
            team.spots_left = team.max_members - team.current_members
            team.save()

        # Notify team owner
        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        Notification.objects.create(
            user=team.owner,
            notification_type='team_joined',
            title='New Member',
            message=f'{user_name} joined your team "{team.name}".',
            related_team=team,
        )

        return Response({
            'message': 'Successfully joined the team',
            'team': {
                'id': team.id,
                'name': team.name,
            }
        }, status=status.HTTP_200_OK)

    except Team.DoesNotExist:
        return Response(
            {'error': 'Team not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


# Match Endpoints

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

        return Response({
            'message': 'Match created successfully',
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


@api_view(['GET'])
@permission_classes([AllowAny])
def user_ratings(request, user_id):
    """Get ratings received by a user"""
    try:
        user = User.objects.get(id=user_id)
    except User.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    ratings = PlayerRating.objects.filter(rated_user=user).select_related('rater', 'match')
    ratings_data = []
    for r in ratings:
        ratings_data.append({
            'id': r.id,
            'rater_name': r.rater.username,
            'match_title': r.match.title,
            'rating': r.rating,
            'comment': r.comment,
            'created_at': r.created_at.isoformat(),
        })

    avg_rating = sum(r['rating'] for r in ratings_data) / len(ratings_data) if ratings_data else 0

    return Response({
        'user_id': user.id,
        'username': user.username,
        'average_rating': round(avg_rating, 1),
        'total_ratings': len(ratings_data),
        'ratings': ratings_data,
    }, status=status.HTTP_200_OK)


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
@permission_classes([AllowAny])
def get_user_stats(request, user_id):
    """Get user statistics"""
    try:
        user = User.objects.get(id=user_id)
    except User.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    matches_as_participant = MatchParticipant.objects.filter(user=user).count()
    
    matches_organized = Match.objects.filter(organizer=user).count()
    
    teams_owned = Team.objects.filter(owner=user).count()
    teams_member = TeamMember.objects.filter(user=user).count()

    user_teams_qs = Team.objects.filter(Q(owner=user) | Q(members__user=user)).distinct()
    leagues_joined = LeagueMember.objects.filter(team__in=user_teams_qs).values('league_id').distinct().count()
    saved_matches = Favorite.objects.filter(user=user, favorite_type='match').count()
    
    ratings_received = PlayerRating.objects.filter(rated_user=user)
    total_ratings = ratings_received.count()
    avg_rating = 0
    if total_ratings > 0:
        avg_rating = sum(r.rating for r in ratings_received) / total_ratings
    
    matches_won = 0
    matches_lost = 0
    matches_draw = 0
    
    user_match_results = MatchResult.objects.filter(
        winner_user_id=user.id,
        match__participants__user=user
    ).distinct().count()
    matches_won = user_match_results
    
    draw_results = MatchResult.objects.filter(
        result_type='draw',
        match__participants__user=user
    ).distinct().count()
    matches_draw = draw_results
    
    matches_lost = matches_as_participant - matches_won - matches_draw

    full_name = f"{user.first_name} {user.last_name}".strip()
    if not full_name:
        full_name = user.username

    phone = ''
    try:
        phone = user.profile.phone
    except UserProfile.DoesNotExist:
        pass

    user_info = {
        'id': user.id,
        'name': full_name,
        'joined': user.date_joined.isoformat() if user.date_joined else None,
    }
    if request.user.is_authenticated and request.user.id == user.id:
        user_info['email'] = user.email
        user_info['phone'] = phone

    return Response({
        'user': user_info,
        'stats': {
            'matches_played': matches_as_participant,
            'matches_organized': matches_organized,
            'matches_hosted': matches_organized,
            'matches_won': matches_won,
            'matches_lost': matches_lost,
            'matches_draw': matches_draw,
            'teams_owned': teams_owned,
            'teams_member': teams_member,
            'leagues_joined': leagues_joined,
            'saved_matches': saved_matches,
            'total_ratings': total_ratings,
            'average_rating': round(avg_rating, 1),
        }
    }, status=status.HTTP_200_OK)


# ── Ranking System ──


def _update_team_sport_individual_elo(match, sport, result):
    participants = list(MatchParticipant.objects.filter(match=match).select_related('user').exclude(team_group=''))
    teams = {'A': [], 'B': []}
    for p in participants:
        if p.team_group in ('A', 'B'):
            teams[p.team_group].append(p)

    if not teams['A'] or not teams['B']:
        return

    # Load all ratings for this sport in one query instead of N get_or_create calls.
    ratings = {
        r.user_id: r
        for r in UserSportRating.objects.filter(user__in=[p.user for p in participants], sport=sport)
    }

    def rating_for(user):
        r = ratings.get(user.id)
        if r is None:
            r = UserSportRating.objects.create(user=user, sport=sport)
            ratings[user.id] = r
        return r

    def avg_elo(group):
        values = [rating_for(p.user).elo_rating for p in group]
        return sum(values) / len(values) if values else 1200

    avg_a = avg_elo(teams['A'])
    avg_b = avg_elo(teams['B'])

    winning_group = result.winning_group
    if winning_group not in ('A', 'B'):
        winning_group = ''

    is_draw = winning_group == '' or result.result_type == 'draw'

    changed = []
    for group_name, group in teams.items():
        own_avg = avg_a if group_name == 'A' else avg_b
        opp_avg = avg_b if group_name == 'A' else avg_a
        for p in group:
            # Free users play but keep a hidden, unchanged rating.
            if not is_premium(p.user):
                continue
            r = rating_for(p.user)
            if is_draw:
                new_own, _ = update_elo_with_matches(own_avg, opp_avg, r.matches_played, 0, draw=True)
                r.draws += 1
            elif group_name == winning_group:
                new_own, _ = update_elo_with_matches(own_avg, opp_avg, r.matches_played, 0)
                r.wins += 1
            else:
                _, new_own = update_elo_with_matches(opp_avg, own_avg, r.matches_played, 0)
                r.losses += 1
            r.elo_rating += round(new_own - r.elo_rating)
            r.matches_played += 1
            changed.append(r)

    if changed:
        UserSportRating.objects.bulk_update(
            changed, ['elo_rating', 'matches_played', 'wins', 'losses', 'draws']
        )


def _compute_rankings(match, result):
    """Update Elo ratings and team rankings after a match result."""
    sport = match.sport

    if result.result_type == 'individual' and result.winner_user_id:
        participants = list(MatchParticipant.objects.filter(match=match).select_related('user'))
        if len(participants) == 2:
            p1 = participants[0]
            p2 = participants[1]
            winner_id = result.winner_user_id
            loser_id = p2.user.id if p1.user.id == winner_id else p1.user.id

            rating1, _ = UserSportRating.objects.get_or_create(user=p1.user, sport=sport)
            rating2, _ = UserSportRating.objects.get_or_create(user=p2.user, sport=sport)

            if p1.user.id == winner_id:
                new_r1, new_r2 = update_elo_with_matches(
                    rating1.elo_rating, rating2.elo_rating,
                    rating1.matches_played, rating2.matches_played,
                )
            else:
                new_r2, new_r1 = update_elo_with_matches(
                    rating2.elo_rating, rating1.elo_rating,
                    rating2.matches_played, rating1.matches_played,
                )

            if is_premium(p1.user):
                rating1.elo_rating = new_r1
                rating1.matches_played += 1
                if p1.user.id == winner_id:
                    rating1.wins += 1
                else:
                    rating1.losses += 1
                rating1.save()

            if is_premium(p2.user):
                rating2.elo_rating = new_r2
                rating2.matches_played += 1
                if p2.user.id == winner_id:
                    rating2.wins += 1
                else:
                    rating2.losses += 1
                rating2.save()

    elif result.result_type == 'draw':
        participants = list(MatchParticipant.objects.filter(match=match).select_related('user'))
        if len(participants) == 2:
            p1 = participants[0]
            p2 = participants[1]
            rating1, _ = UserSportRating.objects.get_or_create(user=p1.user, sport=sport)
            rating2, _ = UserSportRating.objects.get_or_create(user=p2.user, sport=sport)

            new_r1, new_r2 = update_elo_with_matches(
                rating1.elo_rating, rating2.elo_rating,
                rating1.matches_played, rating2.matches_played,
                draw=True,
            )

            if is_premium(p1.user):
                rating1.elo_rating = new_r1
                rating1.matches_played += 1
                rating1.draws += 1
                rating1.save()

            if is_premium(p2.user):
                rating2.elo_rating = new_r2
                rating2.matches_played += 1
                rating2.draws += 1
                rating2.save()

    _update_team_sport_individual_elo(match, sport, result)

    if result.match_type == 'team_vs_team':
        if result.winner_team_id:
            try:
                team1 = match.team
                other_participants = MatchParticipant.objects.filter(match=match).exclude(user__in=team1.members.all())
                team2_id = None
                for mp in other_participants:
                    tm = TeamMember.objects.filter(user=mp.user).exclude(team=team1).first()
                    if tm:
                        team2_id = tm.team.id
                        break

                if team1 and team2_id:
                    t1_rank, _ = TeamRanking.objects.get_or_create(team=team1, sport=sport)
                    t2 = Team.objects.filter(id=team2_id).first()
                    if t2:
                        t2_rank, _ = TeamRanking.objects.get_or_create(team=t2, sport=sport)

                        winner_team = team1 if team1.id == result.winner_team_id else t2
                        loser_team = t2 if team1.id == result.winner_team_id else team1

                        w_rank = TeamRanking.objects.get(team=winner_team, sport=sport)
                        l_rank = TeamRanking.objects.get(team=loser_team, sport=sport)

                        w_rank.wins += 1
                        w_rank.points += 3
                        w_rank.matches_played += 1
                        l_rank.losses += 1
                        l_rank.matches_played += 1

                        score = result.score
                        if score and ' - ' in score:
                            parts = score.split(' - ')
                            try:
                                w_score, l_score = int(parts[0]), int(parts[1])
                                w_rank.goals_for += w_score
                                w_rank.goals_against += l_score
                                l_rank.goals_for += l_score
                                l_rank.goals_against += w_score
                            except (ValueError, IndexError):
                                pass

                        w_rank.save()
                        l_rank.save()
            except (KeyError, AttributeError, ValueError):
                pass

        if result.result_type == 'draw':
            teams_involved = []
            if match.team:
                teams_involved.append(match.team)
            for mp in MatchParticipant.objects.filter(match=match).select_related('user'):
                tm = TeamMember.objects.filter(user=mp.user).exclude(team__in=teams_involved).first()
                if tm and tm.team not in teams_involved:
                    teams_involved.append(tm.team)

            for t in teams_involved:
                rank, _ = TeamRanking.objects.get_or_create(team=t, sport=sport)
                rank.draws += 1
                rank.points += 1
                rank.matches_played += 1
                rank.save()


@api_view(['GET'])
@permission_classes([AllowAny])
def get_individual_rankings(request):
    sport = request.query_params.get('sport', '')
    if sport and sport not in [c[0] for c in Match.SPORT_CHOICES]:
        return Response({'error': 'Invalid sport'}, status=status.HTTP_400_BAD_REQUEST)

    now = timezone.now()
    qs = UserSportRating.objects.select_related('user').filter(
        Q(user__profile__is_premium=True),
    ).filter(
        Q(user__profile__premium_expires__isnull=True) | Q(user__profile__premium_expires__gt=now)
    )
    if sport:
        qs = qs.filter(sport=sport)
    else:
        qs = qs.filter(sport__in=['soccer', 'basketball', 'tennis', 'volleyball'])

    qs = qs.order_by('-elo_rating')[:100]

    data = []
    for rank, rating in enumerate(qs, 1):
        user = rating.user
        name = f"{user.first_name} {user.last_name}".strip() or user.username
        data.append({
            'rank': rank,
            'user_id': user.id,
            'name': name,
            'sport': rating.sport,
            'elo_rating': rating.elo_rating,
            'matches_played': rating.matches_played,
            'wins': rating.wins,
            'losses': rating.losses,
            'draws': rating.draws,
        })

    return Response({'rankings': data}, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([AllowAny])
def get_team_rankings(request):
    sport = request.query_params.get('sport', '')
    if sport and sport not in [c[0] for c in Match.SPORT_CHOICES]:
        return Response({'error': 'Invalid sport'}, status=status.HTTP_400_BAD_REQUEST)

    qs = TeamRanking.objects.select_related('team').all()
    if sport:
        qs = qs.filter(sport=sport)
    else:
        qs = qs.filter(sport__in=['soccer', 'basketball', 'volleyball'])

    qs = list(qs.order_by('-points', '-goals_for')[:100])
    qs.sort(key=lambda t: (t.points, t.goal_difference, t.goals_for), reverse=True)

    data = []
    for rank, tr in enumerate(qs, 1):
        data.append({
            'rank': rank,
            'team_id': tr.team.id,
            'team_name': tr.team.name,
            'sport': tr.sport,
            'wins': tr.wins,
            'losses': tr.losses,
            'draws': tr.draws,
            'points': tr.points,
            'matches_played': tr.matches_played,
            'goal_difference': tr.goal_difference,
            'goals_for': tr.goals_for,
            'goals_against': tr.goals_against,
            'win_rate': tr.win_rate,
        })

    return Response({'rankings': data}, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([AllowAny])
def get_user_form(request, user_id):
    """Last 5 match outcomes (W/L/D) for a user, most recent first."""
    try:
        user = User.objects.get(id=user_id)
    except User.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    match_ids = MatchParticipant.objects.filter(user=user).values_list('match_id', flat=True)
    results = (MatchResult.objects
               .filter(match_id__in=match_ids)
               .select_related('match')
               .order_by('-match__date_time')[:5])

    form = []
    for r in results:
        if r.result_type == 'draw':
            outcome = 'D'
        elif r.winner_user_id == user.id:
            outcome = 'W'
        elif r.winning_group and MatchParticipant.objects.filter(
                match=r.match, user=user, team_group=r.winning_group).exists():
            outcome = 'W'
        elif r.winner_team_id and TeamMember.objects.filter(
                team_id=r.winner_team_id, user=user).exists():
            outcome = 'W'
        else:
            outcome = 'L'
        form.append(outcome)

    return Response({'form': form}, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([AllowAny])
def get_user_elo(request, user_id):
    try:
        user = User.objects.get(id=user_id)
    except User.DoesNotExist:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    ratings = UserSportRating.objects.filter(user=user).order_by('-elo_rating')
    data = []
    for r in ratings:
        data.append({
            'sport': r.sport,
            'elo_rating': r.elo_rating,
            'matches_played': r.matches_played,
            'wins': r.wins,
            'losses': r.losses,
            'draws': r.draws,
        })

    return Response({'ratings': data}, status=status.HTTP_200_OK)


@api_view(['GET', 'POST', 'DELETE'])
def manage_favorites(request, favorite_type, object_id):
    """Get, add, or remove favorites"""
    user = request.user
    if not user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    try:
        favorite_type = validate_favorite_type(favorite_type)
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

    if request.method == 'GET':
        favorites = Favorite.objects.filter(user=user, favorite_type=favorite_type)
        
        if favorite_type == 'team':
            teams = Team.objects.filter(id__in=[f.object_id for f in favorites])
            data = [{'id': t.id, 'name': t.name, 'sport': t.sport, 'logo': ''} for t in teams]
        elif favorite_type == 'match':
            matches = Match.objects.filter(id__in=[f.object_id for f in favorites])
            data = [{'id': m.id, 'title': m.title, 'sport': m.sport, 'date_time': m.date_time.isoformat()} for m in matches]
        elif favorite_type == 'league':
            leagues = League.objects.filter(id__in=[f.object_id for f in favorites])
            data = [{'id': l.id, 'name': l.name, 'sport': l.sport} for l in leagues]
        else:
            data = []

        return Response({'favorites': data}, status=status.HTTP_200_OK)

    elif request.method == 'POST':
        existing = Favorite.objects.filter(user=user, favorite_type=favorite_type, object_id=object_id).first()
        if existing:
            return Response({'message': 'Already favorited', 'favorited': True}, status=status.HTTP_200_OK)

        favorite = Favorite.objects.create(user=user, favorite_type=favorite_type, object_id=object_id)
        return Response({'message': 'Added to favorites', 'favorited': True}, status=status.HTTP_201_CREATED)

    elif request.method == 'DELETE':
        favorite = Favorite.objects.filter(user=user, favorite_type=favorite_type, object_id=object_id).first()
        if favorite:
            favorite.delete()
            return Response({'message': 'Removed from favorites', 'favorited': False}, status=status.HTTP_200_OK)
        return Response({'message': 'Not in favorites', 'favorited': False}, status=status.HTTP_200_OK)


@api_view(['GET'])
def check_favorite(request, favorite_type, object_id):
    """Check if an item is favorited by the user"""
    user = request.user
    if not user.is_authenticated:
        return Response({'favorited': False}, status=status.HTTP_200_OK)

    try:
        favorite_type = validate_favorite_type(favorite_type)
    except ValueError:
        return Response({'favorited': False}, status=status.HTTP_200_OK)

    is_favorited = Favorite.objects.filter(user=user, favorite_type=favorite_type, object_id=object_id).exists()
    return Response({'favorited': is_favorited}, status=status.HTTP_200_OK)


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



@api_view(['GET', 'POST'])
def get_conversations(request):
    """Get all conversations for the user"""
    user = request.user
    if not user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    sent_messages = DirectMessage.objects.filter(sender=user).values_list('recipient_id', flat=True)
    received_messages = DirectMessage.objects.filter(recipient=user).values_list('sender_id', flat=True)
    
    user_ids = set(list(sent_messages) + list(received_messages))
    
    other_users = {u.id: u for u in User.objects.filter(id__in=user_ids)}

    last_messages = {}
    for msg in DirectMessage.objects.filter(
        Q(sender=user) | Q(recipient=user)
    ).order_by('-created_at').only('id', 'message', 'created_at', 'sender_id', 'recipient_id'):
        other_id = msg.recipient_id if msg.sender_id == user.id else msg.sender_id
        if other_id not in last_messages:
            last_messages[other_id] = msg
        # Once every conversation has its latest message we can stop scanning.
        if len(last_messages) == len(user_ids):
            break

    unread_counts = dict(
        DirectMessage.objects.filter(recipient=user, is_read=False)
        .values('sender_id')
        .annotate(count=Count('id'))
        .values_list('sender_id', 'count')
    )

    conversations = []
    for uid in user_ids:
        other_user = other_users.get(uid)
        if not other_user:
            continue
        last_msg = last_messages.get(uid)
        
        full_name = f"{other_user.first_name} {other_user.last_name}".strip()
        if not full_name:
            full_name = other_user.username
            
        conversations.append({
            'user_id': uid,
            'username': other_user.username,
            'name': full_name,
            'last_message': last_msg.message if last_msg else '',
            'last_message_time': last_msg.created_at.isoformat() if last_msg else None,
            'unread_count': unread_counts.get(uid, 0),
        })
    
    conversations.sort(key=lambda x: x['last_message_time'] or '', reverse=True)
    
    return Response({'conversations': conversations}, status=status.HTTP_200_OK)


@api_view(['GET', 'POST'])
def get_messages(request, user_id):
    """Get or send messages with another user"""
    user = request.user
    if not user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)

    if request.method == 'GET':
        messages = DirectMessage.objects.filter(
            (Q(sender=user, recipient_id=user_id) | Q(sender_id=user_id, recipient=user))
        ).order_by('created_at')
        
        DirectMessage.objects.filter(sender_id=user_id, recipient=user, is_read=False).update(is_read=True)
        
        messages_data = []
        for msg in messages:
            messages_data.append({
                'id': msg.id,
                'sender_id': msg.sender.id,
                'sender_name': f"{msg.sender.first_name} {msg.sender.last_name}".strip() or msg.sender.username,
                'message': msg.message,
                'is_read': msg.is_read,
                'created_at': msg.created_at.isoformat(),
                'is_me': msg.sender.id == user.id,
            })
        
        return Response({'messages': messages_data}, status=status.HTTP_200_OK)

    elif request.method == 'POST':
        try:
            raw_message = request.data.get('message')
            message_text = sanitize_text(validate_string(raw_message, 10000, 'Message'))
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            recipient = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
        
        msg = DirectMessage.objects.create(
            sender=user,
            recipient=recipient,
            message=message_text
        )
        
        return Response({
            'message': {
                'id': msg.id,
                'sender_id': msg.sender.id,
                'message': msg.message,
                'created_at': msg.created_at.isoformat(),
                'is_me': True,
            }
        }, status=status.HTTP_201_CREATED)


# ── Referee System ──

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
        
        return Response({
            'success': True,
            'message': 'Booking request sent',
            'booking': _booking_to_dict(booking)
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
            price = validate_decimal(_get(raw, 'price_per_hour', '0'), 0, 99999, 'Price per hour')
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
            price_per_hour=price,
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
            if 'price_per_hour' in request.data:
                venue.price_per_hour = validate_decimal(request.data['price_per_hour'], 0, 999999, 'Price per hour')
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
            hours = max(1, int((end_dt - start_dt).seconds / 3600))
        except (ValueError, TypeError):
            hours = 1
        
        total_price = float(venue.price_per_hour) * hours
        
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
        
        return Response({
            'success': True,
            'booking': _venue_booking_to_dict(booking)
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

@api_view(['POST'])
@throttle_classes([CreateRateThrottle])
def create_tournament(request):
    """
    Create a new tournament
    """
    try:
        try:
            name = validate_string(request.data.get('name', ''), 200, 'Tournament name')
            sport = validate_enum(request.data.get('sport', 'soccer'), SPORT_CHOICES, 'Sport')
            description = sanitize_text(validate_optional_string(request.data.get('description', ''), 5000, 'Description'))
            tournament_format = validate_enum(request.data.get('format', 'single_elimination'), TOURNAMENT_FORMATS, 'Format')
            prize_pool = validate_optional_string(request.data.get('prize_pool', ''), 2000, 'Prize pool')
            entry_fee = validate_decimal(request.data.get('entry_fee', 0), 0, 999999, 'Entry fee')
            max_teams = validate_int(request.data.get('max_teams', 8), 2, 256, 'Max teams')
            rounds = validate_int(request.data.get('rounds', 3), 1, 20, 'Rounds')
            start_date = validate_date_iso(request.data.get('start_date'), 'Start date')
            location = validate_optional_string(request.data.get('location', ''), 200, 'Location')
            rules = sanitize_text(validate_optional_string(request.data.get('rules', ''), 10000, 'Rules'))
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        tournament = Tournament.objects.create(
            name=name,
            sport=sport,
            description=description,
            format=tournament_format,
            prize_pool=prize_pool,
            entry_fee=entry_fee,
            max_teams=max_teams,
            rounds=rounds,
            start_date=start_date,
            location=location,
            rules=rules,
            organizer=request.user,
        )
        
        return Response({
            'success': True,
            'tournament': _tournament_to_dict(tournament)
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['PUT'])
@throttle_classes([SensitiveWriteThrottle])
def edit_tournament(request, tournament_id):
    try:
        tournament = Tournament.objects.get(id=tournament_id, organizer=request.user)
        try:
            if 'name' in request.data:
                tournament.name = validate_string(request.data['name'], 200, 'Tournament name')
            if 'sport' in request.data:
                tournament.sport = validate_enum(request.data['sport'], SPORT_CHOICES, 'Sport')
            if 'description' in request.data:
                tournament.description = sanitize_text(validate_optional_string(request.data['description'], 5000, 'Description'))
            if 'format' in request.data:
                tournament.format = validate_enum(request.data['format'], TOURNAMENT_FORMATS, 'Format')
            if 'prize_pool' in request.data:
                tournament.prize_pool = validate_optional_string(request.data['prize_pool'], 2000, 'Prize pool')
            if 'entry_fee' in request.data:
                tournament.entry_fee = validate_decimal(request.data['entry_fee'], 0, 999999, 'Entry fee')
            if 'max_teams' in request.data:
                tournament.max_teams = validate_int(request.data['max_teams'], 2, 256, 'Max teams')
            if 'rounds' in request.data:
                tournament.rounds = validate_int(request.data['rounds'], 1, 20, 'Rounds')
            if 'start_date' in request.data:
                tournament.start_date = validate_date_iso(request.data['start_date'], 'Start date')
            if 'location' in request.data:
                tournament.location = validate_optional_string(request.data['location'], 200, 'Location')
            if 'rules' in request.data:
                tournament.rules = sanitize_text(validate_optional_string(request.data['rules'], 10000, 'Rules'))
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        tournament.save()
        return Response({'success': True, 'tournament': _tournament_to_dict(tournament)})

    except Tournament.DoesNotExist:
        return Response({'error': 'Tournament not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['DELETE'])
@throttle_classes([SensitiveWriteThrottle])
def delete_tournament(request, tournament_id):
    try:
        tournament = Tournament.objects.get(id=tournament_id, organizer=request.user)
        tournament.delete()
        return Response({'success': True, 'message': 'Tournament deleted successfully'})
    except Tournament.DoesNotExist:
        return Response({'error': 'Tournament not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@permission_classes([AllowAny])
def list_tournaments(request):
    """
    List tournaments with optional filters
    """
    try:
        sport = request.query_params.get('sport', '')
        status = request.query_params.get('status', '')
        
        queryset = Tournament.objects.filter(is_public=True).select_related('organizer', 'venue')
        
        if sport:
            queryset = queryset.filter(sport__icontains=sport)
        if status:
            queryset = queryset.filter(status=status)
        
        tournaments = [_tournament_to_dict(t) for t in queryset]
        
        return Response({
            'success': True,
            'tournaments': tournaments
        })
        
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@permission_classes([AllowAny])
def get_tournament(request, tournament_id):
    """
    Get tournament details with teams and bracket
    """
    try:
        tournament = Tournament.objects.get(id=tournament_id)
        return Response({
            'success': True,
            'tournament': _tournament_to_dict(tournament),
            'teams': [_tournament_team_to_dict(tt) for tt in tournament.teams.select_related('team', 'tournament', 'registered_by').all()],
            'matches': [_tournament_match_to_dict(m) for m in tournament.matches.select_related('team1', 'team2', 'winner').order_by('round_number', 'match_number')],
        })
    except Tournament.DoesNotExist:
        return Response({'error': 'Tournament not found'}, status=status.HTTP_404_NOT_FOUND)


@api_view(['GET'])
def get_my_tournaments(request):
    """
    Get tournaments organized by or registered to current user
    """
    try:
        organized = Tournament.objects.filter(organizer=request.user)
        registered = TournamentTeam.objects.filter(team__members__user=request.user)
        tournament_ids = set([t.id for t in organized] + [rt.tournament_id for rt in registered])
        
        tournaments = Tournament.objects.filter(id__in=tournament_ids).select_related('organizer', 'venue')
        
        return Response({
            'success': True,
            'tournaments': [_tournament_to_dict(t) for t in tournaments]
        })
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def register_team_tournament(request):
    """
    Register a team for a tournament
    """
    try:
        tournament_id = request.data.get('tournament_id')
        team_id = request.data.get('team_id')
        
        with transaction.atomic():
            tournament = Tournament.objects.select_for_update().get(id=tournament_id)
            
            if tournament.current_teams >= tournament.max_teams:
                return Response({'error': 'Tournament is full'}, status=status.HTTP_400_BAD_REQUEST)
            
            if tournament.status not in ['draft', 'registration']:
                return Response({'error': 'Registration closed'}, status=status.HTTP_400_BAD_REQUEST)
            
            team = Team.objects.get(id=team_id)
            
            if TournamentTeam.objects.filter(tournament=tournament, team=team).exists():
                return Response({'error': 'Team already registered'}, status=status.HTTP_400_BAD_REQUEST)
            
            tt = TournamentTeam.objects.create(
                tournament=tournament,
                team=team,
                seed=tournament.current_teams + 1,
                registered_by=request.user
            )
            
            tournament.current_teams += 1
            tournament.save()
        
        return Response({
            'success': True,
            'message': 'Team registered successfully',
            'team': _tournament_team_to_dict(tt)
        }, status=status.HTTP_201_CREATED)
        
    except Tournament.DoesNotExist:
        return Response({'error': 'Tournament not found'}, status=status.HTTP_404_NOT_FOUND)
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def start_tournament(request, tournament_id):
    """
    Start tournament - generate bracket
    """
    try:
        tournament = Tournament.objects.get(id=tournament_id, organizer=request.user)
        
        if tournament.current_teams < 2:
            return Response({'error': 'Need at least 2 teams'}, status=status.HTTP_400_BAD_REQUEST)
        
        if tournament.status == 'live':
            return Response({'error': 'Tournament already started'}, status=status.HTTP_400_BAD_REQUEST)
        
        tournament.status = 'live'
        tournament.save()
        
        _generate_bracket(tournament)
        
        return Response({
            'success': True,
            'message': 'Tournament started',
            'tournament': _tournament_to_dict(tournament)
        })
        
    except Tournament.DoesNotExist:
        return Response({'error': 'Tournament not found or not authorized'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def update_match_result(request, match_id):
    """
    Update match result for tournament matches.
    Updates scores and advances winner to next round.
    """
    try:
        match = TournamentMatch.objects.get(id=match_id)
        
        if match.tournament.organizer != request.user:
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        
        score1 = int(request.data.get('score1', 0))
        score2 = int(request.data.get('score2', 0))

        if score1 == score2:
            return Response({'error': 'Ties are not allowed in elimination brackets'}, status=status.HTTP_400_BAD_REQUEST)

        match.score1 = score1
        match.score2 = score2
        match.status = 'completed'
        
        if score1 > score2:
            match.winner = match.team1
            loser = match.team2
        else:
            match.winner = match.team2
            loser = match.team1
        
        match.save()
        
        if loser:
            loser.status = 'eliminated'
            loser.save()
        
        if match.winner:
            match.winner.status = 'active'
            match.winner.save()
            _advance_winner(match)
        
        _check_tournament_complete(match.tournament)
        
        return Response({
            'success': True,
            'match': _tournament_match_to_dict(match)
        })
        
    except TournamentMatch.DoesNotExist:
        return Response({'error': 'Match not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


def _generate_bracket(tournament):
    import math
    teams = list(tournament.teams.order_by('seed'))
    n = len(teams)
    
    if n < 2:
        return
    
    bracket_size = 1
    while bracket_size < n:
        bracket_size *= 2
    
    num_rounds = int(math.log2(bracket_size))
    
    match_num = 1
    for round_num in range(1, num_rounds + 1):
        if round_num == 1:
            matches_in_round = bracket_size // 2
        else:
            matches_in_round = bracket_size // (2 ** round_num)
        
        for i in range(matches_in_round):
            tm = TournamentMatch.objects.create(
                tournament=tournament,
                round_number=round_num,
                match_number=match_num,
                status='pending',
                bracket_position=f"R{round_num}M{i + 1}"
            )
            match_num += 1
    
    _seed_first_round(teams, bracket_size, tournament)


def _seed_first_round(teams, bracket_size, tournament):
    if len(teams) < 2:
        return
    
    seeded = [None] * bracket_size
    for i, team in enumerate(teams):
        pos = i * 2 if i < bracket_size // 2 else (i - bracket_size // 2) * 2 + 1
        if pos < bracket_size:
            seeded[pos] = team
    
    first_round = tournament.matches.filter(round_number=1).order_by('match_number')
    
    for i, match in enumerate(first_round):
        if 2 * i < len(seeded) and seeded[2 * i]:
            match.team1 = seeded[2 * i]
        if 2 * i + 1 < len(seeded) and seeded[2 * i + 1]:
            match.team2 = seeded[2 * i + 1]
        
        if match.team1 and not match.team2:
            match.winner = match.team1
            match.status = 'completed'
            match.score1 = 0
            match.score2 = -1
        
        if match.team2 and not match.team1:
            match.winner = match.team2
            match.status = 'completed'
            match.score1 = -1
            match.score2 = 0
        
        match.save()
        
        if match.winner:
            _advance_winner(match)


def _advance_winner(match):
    if match.round_number >= match.tournament.rounds:
        return
    
    next_round = match.round_number + 1
    next_match_num = (match.match_number + 1) // 2
    
    try:
        next_match = TournamentMatch.objects.get(
            tournament=match.tournament,
            round_number=next_round,
            match_number=next_match_num
        )
        
        if match.match_number % 2 == 1:
            next_match.team1 = match.winner
        else:
            next_match.team2 = match.winner
        
        next_match.save()
    except TournamentMatch.DoesNotExist:
        pass


def _check_tournament_complete(tournament):
    if tournament.format == 'single_elimination':
        final_matches = tournament.matches.filter(round_number=tournament.rounds, status='completed')
        if final_matches.count() == 1:
            winner_match = final_matches.first()
            if winner_match.winner:
                winner_team = winner_match.winner
                winner_team.status = 'winner'
                winner_team.save()
                
                loser_team = winner_match.team1 if winner_match.team2 == winner_team else winner_match.team2
                if loser_team:
                    loser_team.status = 'runner_up'
                    loser_team.save()
                
                tournament.status = 'completed'
                tournament.save()


def _get_quick_available_slots(venue, target_date, max_slots=4, active_bookings=None):
    opening = venue.opening_time or time(8, 0)
    closing = venue.closing_time or time(22, 0)

    day_start = datetime.combine(target_date, opening)
    day_end = datetime.combine(target_date, closing)
    if day_end <= day_start:
        return []

    if active_bookings is None:
        active_bookings = VenueBooking.objects.filter(
            venue=venue,
            date=target_date,
            status__in=['pending', 'confirmed']
        ).values('start_time', 'end_time')

    blocked = [
        (
            datetime.combine(target_date, b['start_time']),
            datetime.combine(target_date, b['end_time']),
        )
        for b in active_bookings
    ]

    now = timezone.localtime().replace(tzinfo=None)
    cursor = day_start
    slots = []
    while cursor + timedelta(hours=1) <= day_end and len(slots) < max_slots:
        slot_start = cursor
        slot_end = cursor + timedelta(hours=1)

        if target_date == timezone.localdate() and slot_start <= now:
            cursor += timedelta(hours=1)
            continue

        overlaps = any(slot_start < end and slot_end > start for start, end in blocked)
        if not overlaps:
            slots.append({
                'start_time': slot_start.strftime('%H:%M'),
                'end_time': slot_end.strftime('%H:%M'),
                'label': f"{slot_start.strftime('%H:%M')} - {slot_end.strftime('%H:%M')}",
            })

        cursor += timedelta(hours=1)

    return slots


# ── Trust & safety ──

@api_view(['POST'])
def create_report(request):
    try:
        target_user_id = request.data.get('target_user_id')
        match_id = request.data.get('match_id')
        category = validate_enum(request.data.get('category', 'other'), REPORT_CATEGORIES, 'category')
        details = sanitize_text(validate_optional_string(request.data.get('details', ''), 2000, 'Details'))
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

    target = User.objects.filter(id=target_user_id).first() if target_user_id else None
    if target is not None and target.id == request.user.id:
        return Response({'error': 'You cannot report yourself'}, status=status.HTTP_400_BAD_REQUEST)
    match = Match.objects.filter(id=match_id).first() if match_id else None

    Report.objects.create(
        reporter=request.user,
        target_user=target,
        match=match,
        category=category,
        details=details,
    )
    return Response({'success': True, 'message': 'Report submitted'}, status=status.HTTP_201_CREATED)


@api_view(['POST'])
def toggle_block(request):
    target_id = request.data.get('user_id')
    if not target_id:
        return Response({'error': 'user_id is required'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        target_id = int(target_id)
    except (TypeError, ValueError):
        return Response({'error': 'Invalid user_id'}, status=status.HTTP_400_BAD_REQUEST)
    if target_id == request.user.id:
        return Response({'error': 'You cannot block yourself'}, status=status.HTTP_400_BAD_REQUEST)
    target = User.objects.filter(id=target_id).first()
    if not target:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)

    existing = Block.objects.filter(blocker=request.user, blocked=target).first()
    if existing:
        existing.delete()
        return Response({'blocked': False, 'message': 'Unblocked'})
    Block.objects.create(blocker=request.user, blocked=target)
    return Response({'blocked': True, 'message': 'Blocked'})


# ── Push devices + reminders ──

@api_view(['POST'])
def register_device(request):
    try:
        token = validate_string(request.data.get('token'), 500, 'token')
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
    device_type = (request.data.get('device_type') or 'android')
    if device_type not in ('android', 'ios', 'web'):
        device_type = 'android'
    DeviceToken.objects.update_or_create(
        token=token,
        defaults={'user': request.user, 'device_type': device_type, 'is_active': True},
    )
    return Response({'success': True})


@api_view(['POST'])
def unregister_device(request):
    token = request.data.get('token')
    if token:
        DeviceToken.objects.filter(user=request.user, token=token).update(is_active=False)
    return Response({'success': True})


@api_view(['POST'])
@permission_classes([AllowAny])
def run_reminders(request):
    """External-cron entry point (no Celery in this stack). Protected by a secret."""
    secret = getattr(settings, 'REMINDER_SECRET', '')
    provided = request.headers.get('X-Reminder-Secret') or request.data.get('secret', '')
    if not secret or provided != secret:
        return Response({'error': 'unauthorized'}, status=status.HTTP_401_UNAUTHORIZED)

    from io import StringIO
    from django.core.management import call_command
    out = StringIO()
    call_command('send_match_reminders', stdout=out)
    return Response({'success': True, 'output': out.getvalue()})


# ── Social graph ──

def _user_card(u, request_user=None):
    image = ''
    try:
        image = u.profile.profile_image or ''
    except UserProfile.DoesNotExist:
        pass
    return {
        'user_id': u.id,
        'name': display_name(u),
        'profile_image': image,
        'is_following': Follow.objects.filter(
            follower=request_user, following=u).exists() if request_user else False,
    }


@api_view(['GET'])
def social_me(request):
    me = request.user
    profile = UserProfile.get_or_create_for_user(me)
    return Response({
        'referral_code': profile.referral_code,
        'referral_credit': profile.referral_credit,
        'following_count': Follow.objects.filter(follower=me).count(),
        'followers_count': Follow.objects.filter(following=me).count(),
    })


@api_view(['POST'])
def follow_toggle(request):
    target_id = request.data.get('user_id')
    try:
        target_id = int(target_id)
    except (TypeError, ValueError):
        return Response({'error': 'user_id is required'}, status=status.HTTP_400_BAD_REQUEST)
    if target_id == request.user.id:
        return Response({'error': 'You cannot follow yourself'}, status=status.HTTP_400_BAD_REQUEST)
    target = User.objects.filter(id=target_id).first()
    if not target:
        return Response({'error': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
    existing = Follow.objects.filter(follower=request.user, following=target).first()
    if existing:
        existing.delete()
        return Response({'following': False})
    Follow.objects.create(follower=request.user, following=target)
    return Response({'following': True})


@api_view(['GET'])
def list_following(request):
    ids = Follow.objects.filter(follower=request.user).values_list('following_id', flat=True)
    users = User.objects.filter(id__in=ids)[:100]
    return Response({'users': [_user_card(u, request.user) for u in users]})


@api_view(['GET'])
def list_followers(request):
    ids = Follow.objects.filter(following=request.user).values_list('follower_id', flat=True)
    users = User.objects.filter(id__in=ids)[:100]
    return Response({'users': [_user_card(u, request.user) for u in users]})


@api_view(['GET'])
def list_teammates(request):
    match_ids = MatchParticipant.objects.filter(user=request.user).values_list('match_id', flat=True)
    co_match = MatchParticipant.objects.filter(match_id__in=match_ids).exclude(
        user=request.user).values_list('user_id', flat=True)
    team_ids = TeamMember.objects.filter(user=request.user).values_list('team_id', flat=True)
    co_team = TeamMember.objects.filter(team_id__in=team_ids).exclude(
        user=request.user).values_list('user_id', flat=True)
    ids = set(list(co_match) + list(co_team))
    users = User.objects.filter(id__in=ids)[:100]
    return Response({'users': [_user_card(u, request.user) for u in users]})


@api_view(['GET'])
def list_referrals(request):
    refs = Referral.objects.filter(referrer=request.user).select_related('referred')
    return Response({'referrals': [{
        'name': display_name(r.referred) if r.referred else '—',
        'credit': r.credit,
        'created_at': r.created_at.isoformat(),
    } for r in refs]})


# ── Phone verification (OTP) ──

@api_view(['POST'])
def send_phone_code(request):
    profile = UserProfile.get_or_create_for_user(request.user)
    phone = (request.data.get('phone') or profile.phone or '').strip()
    if not phone:
        return Response({'error': 'Add a phone number first'}, status=status.HTTP_400_BAD_REQUEST)
    code = f'{random.randint(0, 999999):06d}'
    profile.phone = phone
    profile.phone_code = code
    profile.phone_code_expires = timezone.now() + timedelta(minutes=10)
    profile.save(update_fields=['phone', 'phone_code', 'phone_code_expires'])
    sent = send_sms(phone, f'Your VYRO verification code is {code}')
    payload = {'success': True, 'sent': sent}
    if settings.DEBUG and not sent:
        payload['dev_code'] = code
    return Response(payload)


@api_view(['POST'])
def verify_phone(request):
    code = (request.data.get('code') or '').strip()
    profile = UserProfile.get_or_create_for_user(request.user)
    if not profile.phone_code or profile.phone_code != code:
        return Response({'error': 'Invalid code'}, status=status.HTTP_400_BAD_REQUEST)
    if not profile.phone_code_expires or profile.phone_code_expires < timezone.now():
        return Response({'error': 'Code expired — request a new one'}, status=status.HTTP_400_BAD_REQUEST)
    profile.phone_verified = True
    profile.phone_code = ''
    profile.phone_code_expires = None
    profile.save(update_fields=['phone_verified', 'phone_code', 'phone_code_expires'])
    return Response({'success': True, 'message': 'Phone verified'})


@api_view(['GET'])
def phone_status(request):
    profile = UserProfile.get_or_create_for_user(request.user)
    return Response({'phone': profile.phone, 'phone_verified': profile.phone_verified})

