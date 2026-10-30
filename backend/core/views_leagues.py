from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.utils import timezone
from django.db import transaction
from django.db.models import Q
from .models import (
    Match, MatchParticipant, PlatformTransaction, Team, TeamMember, League, LeagueMember,
    LeagueFixture, Venue,
)
from .entitlements import (
    is_premium, team_all_premium,
)
from .monetization import league_fee, record_transaction
from .push import notify
from .serializers import (
    err_msg as _err_msg, league_summary, league_standing, league_fixture_to_dict,
)
from .validators import (
    SensitiveWriteThrottle, SPORT_CHOICES, validate_string, validate_optional_string, validate_int,
    validate_decimal, validate_enum, validate_date_iso, validate_boolean,
)
from .analytics import track
from .view_shared import (
    _apply_fixture_result, _generate_round_robin, league_standings,
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
        ).select_related('organizer').prefetch_related('members__team').order_by('start_date')[:20]

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
        # Teams the user owns or is a member of
        teams = Team.objects.filter(
            Q(owner=request.user) | Q(members__user=request.user)
        ).distinct()
        
        # Get league memberships for those teams
        memberships = LeagueMember.objects.filter(
            team__in=teams
        ).select_related('league', 'team').distinct()

        data = []
        for m in memberships:
            league = m.league
            data.append({
                'league_id': league.id,
                'league_name': league.name,
                'sport': league.sport,
                'format': league.format,
                'status': league.status,
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
            double_round_robin = validate_boolean(request.data.get('double_round_robin', False), 'Double round robin')
            points_win = validate_int(request.data.get('points_win', 3), 0, 10, 'Points for a win')
            points_draw = validate_int(request.data.get('points_draw', 1), 0, 10, 'Points for a draw')
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
            double_round_robin=double_round_robin,
            points_win=points_win,
            points_draw=points_draw,
            organizer=request.user,
        )

        track(request.user, 'league_created', {'league_id': league.id, 'sport': league.sport})

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
        has_fixtures = league.fixtures.exists()
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
                if has_fixtures:
                    return Response({'error': 'Entry fee cannot change once the league has started'},
                                    status=status.HTTP_400_BAD_REQUEST)
                league.entry_fee = validate_decimal(request.data['entry_fee'], 0, 999999, 'Entry fee')
            if 'prize' in request.data:
                league.prize = validate_optional_string(request.data['prize'], 2000, 'Prize')
            if 'location' in request.data:
                league.location = validate_optional_string(request.data['location'], 200, 'Location')
            if 'start_date' in request.data:
                league.start_date = validate_date_iso(request.data['start_date'], 'Start date')
            if 'is_active' in request.data:
                league.is_active = validate_boolean(request.data['is_active'], 'Is active')
            if 'double_round_robin' in request.data:
                if has_fixtures:
                    return Response({'error': 'Schedule cannot change once fixtures exist'},
                                    status=status.HTTP_400_BAD_REQUEST)
                league.double_round_robin = validate_boolean(request.data['double_round_robin'], 'Double round robin')
            if 'points_win' in request.data:
                if has_fixtures:
                    return Response({'error': 'Scoring cannot change once fixtures exist'},
                                    status=status.HTTP_400_BAD_REQUEST)
                league.points_win = validate_int(request.data['points_win'], 0, 10, 'Points for a win')
            if 'points_draw' in request.data:
                if has_fixtures:
                    return Response({'error': 'Scoring cannot change once fixtures exist'},
                                    status=status.HTTP_400_BAD_REQUEST)
                league.points_draw = validate_int(request.data['points_draw'], 0, 10, 'Points for a draw')
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
    Join a league with a team (registration window only)
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

            if league.status != 'registration':
                return Response({'error': 'Registration is closed for this league'},
                                status=status.HTTP_400_BAD_REQUEST)

            if league.start_date <= timezone.now():
                return Response({'error': 'Registration is closed — the league has started'},
                                status=status.HTTP_400_BAD_REQUEST)

            if not is_premium(request.user):
                return Response({
                    'error': 'Only Premium users can join leagues.',
                    'upgrade_required': True,
                }, status=status.HTTP_402_PAYMENT_REQUIRED)

            if not team_all_premium(team):
                return Response({
                    'error': 'All team members need Victiqo Premium to join a league.',
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

            if league.entry_fee > 0:
                cut = league_fee(league.entry_fee)
                record_transaction(
                    'league_fee', cut, payer=request.user,
                    reference_type='league', reference_id=league.id,
                    note=f'Entry cut for "{league.name}" ({team.name})',
                )

        track(request.user, 'league_joined', {
            'league_id': league.id, 'entry_fee': str(league.entry_fee),
        })

        notify(
            league.organizer, 'general', 'Team joined your league',
            f'{team.name} joined "{league.name}".',
        )

        return Response({
            'message': 'Team joined league successfully',
            'entry_fee': str(league.entry_fee),
        }, status=status.HTTP_201_CREATED)

    except League.DoesNotExist:
        return Response({'error': 'League not found'}, status=status.HTTP_404_NOT_FOUND)
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def remove_league_team(request, league_id):
    """Organizer removes a team — before the season starts."""
    try:
        league = League.objects.get(id=league_id, organizer=request.user)
    except League.DoesNotExist:
        return Response({'error': 'League not found'}, status=status.HTTP_404_NOT_FOUND)

    if league.status != 'registration':
        return Response({'error': 'Teams can only be removed before the league starts'},
                        status=status.HTTP_400_BAD_REQUEST)

    try:
        team_id = int(request.data.get('team_id') or 0)
    except (TypeError, ValueError):
        return Response({'error': 'team_id is required'}, status=status.HTTP_400_BAD_REQUEST)

    membership = LeagueMember.objects.filter(league=league, team_id=team_id).first()
    if not membership:
        return Response({'error': 'Team is not in this league'}, status=status.HTTP_404_NOT_FOUND)

    team_name = membership.team.name
    membership.delete()
    league.current_teams = LeagueMember.objects.filter(league=league).count()
    league.save(update_fields=['current_teams'])

    notify(membership.team.owner, 'general', 'Removed from league',
           f'{team_name} was removed from "{league.name}".')

    return Response({'success': True, 'message': f'{team_name} removed',
                     'current_teams': league.current_teams})




@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def start_league(request, league_id):
    """Start the season: lock registrations and generate the fixture list."""
    try:
        league = League.objects.get(id=league_id, organizer=request.user)
    except League.DoesNotExist:
        return Response({'error': 'League not found'}, status=status.HTTP_404_NOT_FOUND)

    if league.status == 'live':
        return Response({'error': 'League already started'}, status=status.HTTP_400_BAD_REQUEST)
    if league.status in ('completed', 'cancelled'):
        return Response({'error': f'League is {league.status}'}, status=status.HTTP_400_BAD_REQUEST)
    if league.fixtures.exists():
        return Response({'error': 'This league already has a schedule'},
                        status=status.HTTP_400_BAD_REQUEST)

    members = LeagueMember.objects.filter(league=league).select_related('team__owner')
    if members.count() < 2:
        return Response({'error': 'Need at least 2 teams to start'}, status=status.HTTP_400_BAD_REQUEST)

    with transaction.atomic():
        league.status = 'live'
        league.save(update_fields=['status'])
        fixtures = _generate_round_robin(league)

    for member in members:
        owner = member.team.owner
        if owner.id != league.organizer_id:
            notify(owner, 'general', 'League started',
                   f'"{league.name}" is live — {len(fixtures)} fixtures scheduled.')

    return Response({
        'success': True,
        'message': f'League started with {len(fixtures)} fixtures',
        'fixtures': len(fixtures),
        'league': league_summary(league),
    })




@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def record_fixture_result(request, fixture_id):
    """Organizer records (or corrects) a fixture score; standings update."""
    try:
        fixture = LeagueFixture.objects.select_related('league', 'home_team', 'away_team').get(id=fixture_id)
    except LeagueFixture.DoesNotExist:
        return Response({'error': 'Fixture not found'}, status=status.HTTP_404_NOT_FOUND)

    league = fixture.league
    if league.organizer_id != request.user.id:
        return Response({'error': 'Only the league organizer can record results'},
                        status=status.HTTP_403_FORBIDDEN)
    if league.status != 'live':
        return Response({'error': 'Results can only be recorded while the league is live'},
                        status=status.HTTP_400_BAD_REQUEST)

    try:
        home_score = validate_int(request.data.get('home_score', 0), 0, 999, 'Home score')
        away_score = validate_int(request.data.get('away_score', 0), 0, 999, 'Away score')
        walkover = validate_enum(request.data.get('walkover', ''), {'', 'home', 'away'}, 'walkover')
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

    if walkover == 'home':
        home_score, away_score = max(3, home_score), 0
    elif walkover == 'away':
        home_score, away_score = 0, max(3, away_score)

    with transaction.atomic():
        _apply_fixture_result(fixture, home_score, away_score, walkover=walkover in ('home', 'away'))

    league.refresh_from_db()
    for team in (fixture.home_team, fixture.away_team):
        if team.owner_id != request.user.id:
            notify(team.owner, 'general', 'League result recorded',
                   f'{fixture.home_team.name} {fixture.home_score}–{fixture.away_score} '
                   f'{fixture.away_team.name} ({league.name}).')

    return Response({
        'success': True,
        'fixture': league_fixture_to_dict(fixture),
        'league_status': league.status,
        'champion_team_id': league.champion_id,
    })




@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def reschedule_fixture(request, fixture_id):
    """Organizer moves a fixture (and its linked match) to a new kickoff."""
    try:
        fixture = LeagueFixture.objects.select_related('league').get(id=fixture_id)
    except LeagueFixture.DoesNotExist:
        return Response({'error': 'Fixture not found'}, status=status.HTTP_404_NOT_FOUND)

    league = fixture.league
    if league.organizer_id != request.user.id:
        return Response({'error': 'Only the league organizer can reschedule'},
                        status=status.HTTP_403_FORBIDDEN)
    if league.status in ('completed', 'cancelled'):
        return Response({'error': f'League is {league.status}'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        kickoff = validate_date_iso(request.data.get('kickoff'), 'Kickoff')
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

    fixture.kickoff = kickoff
    fixture.save(update_fields=['kickoff'])
    if fixture.match_id:
        fixture.match.date_time = kickoff
        fixture.match.save(update_fields=['date_time'])

    return Response({'success': True, 'fixture': league_fixture_to_dict(fixture)})




@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def schedule_fixture(request, fixture_id):
    """Organizer creates a real Match for a fixture (venue, time, players)."""
    try:
        fixture = LeagueFixture.objects.select_related('league', 'home_team', 'away_team').get(id=fixture_id)
    except LeagueFixture.DoesNotExist:
        return Response({'error': 'Fixture not found'}, status=status.HTTP_404_NOT_FOUND)

    league = fixture.league
    if league.organizer_id != request.user.id:
        return Response({'error': 'Only the league organizer can schedule fixtures'},
                        status=status.HTTP_403_FORBIDDEN)
    if league.status not in ('registration', 'live'):
        return Response({'error': f'League is {league.status}'}, status=status.HTTP_400_BAD_REQUEST)
    if fixture.match_id:
        return Response({'error': 'This fixture already has a match'},
                        status=status.HTTP_400_BAD_REQUEST)

    raw_date = request.data.get('date_time')
    try:
        date_time = validate_date_iso(raw_date, 'Date time') if raw_date else fixture.kickoff
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
    if not date_time:
        return Response({'error': 'date_time is required'}, status=status.HTTP_400_BAD_REQUEST)

    venue = None
    venue_id = request.data.get('venue_id')
    if venue_id:
        venue = Venue.objects.filter(id=venue_id).first()
        if venue is None:
            return Response({'error': 'Venue not found'}, status=status.HTTP_404_NOT_FOUND)

    try:
        location = validate_optional_string(
            request.data.get('location') or league.location or (venue.city if venue else 'TBD'),
            200, 'Location')
    except ValueError as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

    match = Match.objects.create(
        title=f'{fixture.home_team.name} vs {fixture.away_team.name}',
        sport=league.sport,
        description=f'{league.name} — Round {fixture.round_number}',
        location=location,
        date_time=date_time,
        max_players=max(2, fixture.home_team.max_members + fixture.away_team.max_members),
        price=0,
        organizer=league.organizer,
        team=fixture.home_team,
        league=league,
        venue=venue,
    )
    MatchParticipant.objects.create(match=match, user=league.organizer)

    fixture.match = match
    if not fixture.kickoff:
        fixture.kickoff = date_time
    fixture.save(update_fields=['match', 'kickoff'])

    for team in (fixture.home_team, fixture.away_team):
        if team.owner_id != request.user.id:
            notify(team.owner, 'general', 'Fixture scheduled',
                   f'{fixture.home_team.name} vs {fixture.away_team.name} — '
                   f'{date_time.strftime("%b %d, %H:%M")} ({league.name}).',
                   match=match)

    return Response({
        'success': True,
        'match_id': match.id,
        'fixture': league_fixture_to_dict(fixture),
    })




@api_view(['POST'])
@throttle_classes([SensitiveWriteThrottle])
def cancel_league(request, league_id):
    """Organizer cancels the league and marks collected entry fees refunded."""
    try:
        league = League.objects.get(id=league_id, organizer=request.user)
    except League.DoesNotExist:
        return Response({'error': 'League not found'}, status=status.HTTP_404_NOT_FOUND)

    if league.status == 'completed':
        return Response({'error': 'A completed league cannot be cancelled'},
                        status=status.HTTP_400_BAD_REQUEST)
    if league.status == 'cancelled':
        return Response({'error': 'League is already cancelled'}, status=status.HTTP_400_BAD_REQUEST)

    league.status = 'cancelled'
    league.is_active = False
    league.save(update_fields=['status', 'is_active'])

    refunded = PlatformTransaction.objects.filter(
        kind='league_fee', reference_type='league', reference_id=league.id,
    ).update(status='refunded')

    for member in LeagueMember.objects.filter(league=league).select_related('team__owner'):
        owner = member.team.owner
        if owner.id != league.organizer_id:
            notify(owner, 'general', 'League cancelled',
                   f'"{league.name}" was cancelled by the organizer.')

    return Response({'success': True, 'message': 'League cancelled',
                     'entry_fees_refunded': refunded})




@api_view(['GET'])
@permission_classes([AllowAny])
def get_league_details(request, league_id):
    """
    Get league details, standings and fixtures
    """
    try:
        league = League.objects.select_related('organizer', 'champion').get(id=league_id)

        my_team_ids = set()
        if request.user.is_authenticated:
            my_team_ids = set(
                Team.objects.filter(owner=request.user).values_list('id', flat=True)
            ) | set(
                TeamMember.objects.filter(user=request.user).values_list('team_id', flat=True)
            )

        members = league_standings(league)
        standings = [
            league_standing(m, i + 1, is_mine=m.team_id in my_team_ids)
            for i, m in enumerate(members)
        ]

        fixtures = [
            league_fixture_to_dict(f)
            for f in league.fixtures.select_related('home_team', 'away_team')
                             .order_by('round_number', 'kickoff', 'id')
        ]

        summary = league_summary(league)
        summary['is_organizer'] = (
            request.user.is_authenticated and league.organizer_id == request.user.id
        )

        return Response({
            'league': summary,
            'standings': standings,
            'fixtures': fixtures,
        }, status=status.HTTP_200_OK)

    except League.DoesNotExist:
        return Response({'error': 'League not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
