from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.utils import timezone
from django.db import transaction
from .models import Team, League, LeagueMember
from .entitlements import (
    is_premium, team_all_premium,
)
from .serializers import (
    err_msg as _err_msg, league_summary, league_standing,
)
from .validators import (
    SensitiveWriteThrottle, SPORT_CHOICES, validate_string, validate_optional_string, validate_int, validate_decimal,
    validate_enum, validate_date_iso, validate_boolean,
)




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
                    'error': 'All team members need Rivalink Premium to join a league.',
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
