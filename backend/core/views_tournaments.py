from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.db import transaction
from .models import Team, TeamMember, Tournament, TournamentTeam, TournamentMatch
from .monetization import (
    tournament_fee, record_transaction,
)
from .serializers import (
    err_msg as _err_msg, tournament_to_dict as _tournament_to_dict, tournament_team_to_dict as _tournament_team_to_dict, tournament_match_to_dict as _tournament_match_to_dict,
)
from .validators import (
    CreateRateThrottle, SensitiveWriteThrottle, SPORT_CHOICES, TOURNAMENT_FORMATS, validate_string, validate_optional_string,
    validate_int, validate_decimal, validate_enum, sanitize_text, validate_date_iso,
)


from .view_shared import (
    _generate_bracket, _advance_winner, _check_tournament_complete,
)


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
            
            is_owner = team.owner_id == request.user.id
            is_admin = TeamMember.objects.filter(
                team=team, user=request.user, role__in=['owner', 'admin']).exists()
            if not is_owner and not is_admin:
                return Response({'error': 'Only team owners/admins can register this team'},
                                status=status.HTTP_403_FORBIDDEN)
            
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

            entry_fee = tournament_fee(tournament.entry_fee)
            record_transaction(
                'tournament_fee', entry_fee, payer=request.user,
                reference_type='tournament', reference_id=tournament.id,
                note=f'Entry fee cut for "{tournament.name}" ({team.name})',
            )

        return Response({
            'success': True,
            'message': 'Team registered successfully',
            'team': _tournament_team_to_dict(tt),
            'platform_fee': str(entry_fee),
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
        
        if tournament.status == 'completed':
            return Response({'error': 'Tournament is already completed'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Never regenerate a bracket that already exists (avoids duplicate rows).
        if TournamentMatch.objects.filter(tournament=tournament).exists():
            return Response({'error': 'This tournament already has a bracket'},
                            status=status.HTTP_400_BAD_REQUEST)
        
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
        
        try:
            score1 = validate_int(request.data.get('score1', 0), 0, 9999, 'score1')
            score2 = validate_int(request.data.get('score2', 0), 0, 9999, 'score2')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        if not match.team1 or not match.team2:
            return Response({'error': 'Both teams must be set before recording a result'},
                            status=status.HTTP_400_BAD_REQUEST)

        if match.status == 'completed':
            return Response({'error': 'Match result already recorded'},
                            status=status.HTTP_400_BAD_REQUEST)

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
