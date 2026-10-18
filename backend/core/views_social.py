from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.contrib.auth.models import User
from django.db.models import Q, Count
from django.conf import settings
from django.utils import timezone
from datetime import timedelta
import random
from .models import (
    UserProfile, Team, TeamMember, Match, MatchParticipant, Notification,
    League, LeagueMember, PlayerRating, MatchResult, Favorite, DirectMessage,
    UserSportRating, TeamRanking, Report, Block, DeviceToken, Follow,
    Referral,
)
from .sms import send_sms
from .serializers import (
    err_msg as _err_msg, display_name,
)
from .validators import (
    REPORT_CATEGORIES, validate_string, validate_optional_string, validate_enum, sanitize_text, validate_favorite_type,
)


from .view_shared import (
    _user_card,
)


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
    sent = send_sms(phone, f'Your Rivalink verification code is {code}')
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
