"""Shared response serializers and error helpers.

Kept as plain functions (the API builds dicts by hand) so multiple views can
reuse one canonical shape instead of duplicating the same dict everywhere.
"""
from django.conf import settings
from django.utils import timezone
from rest_framework import status as http_status
from rest_framework.response import Response


# ── Error handling ──

def err_msg(exc):
    """Client-safe error text.

    Validation failures (ValueError from core.validators) are safe to surface;
    everything else is hidden unless DEBUG is on.
    """
    if isinstance(exc, ValueError):
        return str(exc)
    if settings.DEBUG:
        return str(exc)
    return 'An unexpected error occurred'


def error_response(exc, status_code=http_status.HTTP_500_INTERNAL_SERVER_ERROR):
    return Response({'error': err_msg(exc)}, status=status_code)


# ── Shared helpers ──

def display_name(user):
    return f"{user.first_name} {user.last_name}".strip() or user.username


# ── Matches ──

def match_summary(match):
    participants = list(match.participants.all())[:3]
    return {
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
        'skill_level': getattr(match, 'skill_level', 'any'),
        'organizer_id': match.organizer.id,
        'organizer_name': display_name(match.organizer),
        'participants_preview': [display_name(p.user) for p in participants],
    }


def _match_outcome(match, user, joined_ids, my_team_ids):
    """W/D/L for the user once a result is confirmed, else None."""
    result = getattr(match, 'result', None)
    if not result or result.status != 'confirmed':
        return None
    if result.result_type == 'draw':
        return 'draw'
    participated = match.id in joined_ids or match.organizer_id == user.id
    if result.winner_user_id is not None:
        if result.winner_user_id == user.id:
            return 'win'
        return 'loss' if participated else None
    if result.winner_team_id is not None and my_team_ids:
        if result.winner_team_id in my_team_ids:
            return 'win'
        if {result.team1_id, result.team2_id} & my_team_ids:
            return 'loss'
    return None


def match_my(match, user, joined_ids, saved_ids, my_team_ids=None):
    data = match_summary(match)
    data.update({
        'is_organizer': match.organizer.id == user.id,
        'is_joined': match.id in joined_ids,
        'is_saved': match.id in saved_ids,
        'match_status': 'upcoming' if match.date_time >= timezone.now() else 'past',
        'outcome': _match_outcome(match, user, joined_ids, my_team_ids or set()),
    })
    return data


def match_history(match, user):
    return {
        'id': match.id,
        'title': match.title,
        'sport': match.sport,
        'location': match.location,
        'date_time': match.date_time.isoformat(),
        'max_players': match.max_players,
        'current_players': match.current_players,
        'price': str(match.price),
        'organizer_name': display_name(match.organizer),
        'is_organizer': match.organizer.id == user.id,
        'was_cancelled': not match.is_active,
    }


# ── Leagues ──

def league_summary(league):
    recent_members = sorted(league.members.all(), key=lambda m: m.joined_at)[:3]
    return {
        'id': league.id,
        'name': league.name,
        'sport': league.sport,
        'description': league.description,
        'format': league.format,
        'max_teams': league.max_teams,
        'current_teams': league.current_teams,
        'entry_fee': str(league.entry_fee),
        'prize': league.prize,
        'start_date': league.start_date.isoformat(),
        'end_date': league.end_date.isoformat() if league.end_date else None,
        'location': league.location,
        'status': league.status,
        'points_win': league.points_win,
        'points_draw': league.points_draw,
        'double_round_robin': league.double_round_robin,
        'champion_team_id': league.champion_id,
        'champion_team_name': league.champion.name if league.champion else None,
        'is_active': league.is_active,
        'team_names': [m.team.name for m in recent_members],
        'organizer_name': display_name(league.organizer),
    }


def league_fixture_to_dict(fixture):
    return {
        'id': fixture.id,
        'league_id': fixture.league_id,
        'round_number': fixture.round_number,
        'home_team_id': fixture.home_team_id,
        'home_team_name': fixture.home_team.name,
        'away_team_id': fixture.away_team_id,
        'away_team_name': fixture.away_team.name,
        'kickoff': fixture.kickoff.isoformat() if fixture.kickoff else None,
        'match_id': fixture.match_id,
        'home_score': fixture.home_score,
        'away_score': fixture.away_score,
        'is_walkover': fixture.is_walkover,
        'status': fixture.status,
    }


def league_standing(member, rank, is_mine=False):
    return {
        'rank': rank,
        'team_id': member.team.id,
        'team_name': member.team.name,
        'wins': member.wins,
        'losses': member.losses,
        'draws': member.draws,
        'points': member.points,
        'goals_for': member.goals_for,
        'goals_against': member.goals_against,
        'goal_difference': member.goal_difference,
        'matches_played': member.matches_played,
        'win_rate': round(member.win_rate, 1),
        'prev_rank': member.prev_rank,
        'is_mine': is_mine,
    }


# ── Referees ──

def referee_to_dict(referee):
    return {
        'id': referee.id,
        'user_id': referee.user.id,
        'name': display_name(referee.user),
        'email': referee.user.email if getattr(referee, '_expose_email', False) else '',
        'sports': referee.sport_list,
        'sports_string': referee.sports,
        'experience_years': referee.experience_years,
        'certification': referee.certification,
        'bio': referee.bio,
        'hourly_rate': float(referee.hourly_rate),
        'location': referee.location,
        'is_available': referee.is_available,
        'verification_status': referee.verification_status,
        'average_rating': float(referee.average_rating),
        'total_matches': referee.total_matches,
    }


def booking_to_dict(booking):
    return {
        'id': booking.id,
        'referee_id': booking.referee.id,
        'referee_name': display_name(booking.referee.user),
        'match_id': booking.match.id,
        'match_title': booking.match.title,
        'booked_by_id': booking.booked_by.id,
        'booked_by_name': display_name(booking.booked_by),
        'status': booking.status,
        'fee': float(booking.fee),
        'notes': booking.notes,
        'created_at': booking.created_at.isoformat(),
    }


# ── Venues ──

def venue_to_dict(venue):
    return {
        'id': venue.id,
        'owner_id': venue.owner.id,
        'owner_name': display_name(venue.owner),
        'name': venue.name,
        'description': venue.description,
        'address': venue.address,
        'city': venue.city,
        'location': venue.location,
        'sports': venue.sport_list,
        'sports_string': venue.sports,
        'slot_price': float(venue.slot_price),
        'capacity': venue.capacity,
        'amenities': venue.amenities_list,
        'amenities_string': venue.amenities,
        'images': venue.image_list,
        'images_string': venue.images,
        'opening_time': str(venue.opening_time) if venue.opening_time else None,
        'closing_time': str(venue.closing_time) if venue.closing_time else None,
        'is_active': venue.is_active,
        'is_available': venue.is_available,
        'verification_status': venue.verification_status,
        'average_rating': float(venue.average_rating),
        'total_bookings': venue.total_bookings,
    }


def venue_booking_to_dict(booking):
    return {
        'id': booking.id,
        'venue_id': booking.venue.id,
        'venue_name': booking.venue.name,
        'match_id': booking.match.id if booking.match else None,
        'match_title': booking.match.title if booking.match else None,
        'booked_by_id': booking.booked_by.id,
        'booked_by_name': display_name(booking.booked_by),
        'date': str(booking.date),
        'start_time': str(booking.start_time),
        'end_time': str(booking.end_time),
        'hours': booking.hours,
        'total_price': float(booking.total_price),
        'status': booking.status,
        'payment_status': booking.payment_status,
        'paid_at': booking.paid_at.isoformat() if booking.paid_at else None,
        'notes': booking.notes,
        'created_at': booking.created_at.isoformat(),
    }


# ── Tournaments ──

def tournament_to_dict(t):
    return {
        'id': t.id,
        'name': t.name,
        'sport': t.sport,
        'description': t.description,
        'format': t.format,
        'format_display': t.get_format_display(),
        'prize_pool': t.prize_pool,
        'entry_fee': float(t.entry_fee),
        'max_teams': t.max_teams,
        'current_teams': t.current_teams,
        'rounds': t.rounds,
        'status': t.status,
        'status_display': t.get_status_display(),
        'start_date': t.start_date.isoformat() if t.start_date else None,
        'end_date': t.end_date.isoformat() if t.end_date else None,
        'organizer_id': t.organizer.id,
        'organizer_name': display_name(t.organizer),
        'venue_id': t.venue.id if t.venue else None,
        'venue_name': t.venue.name if t.venue else None,
        'location': t.location,
        'rules': t.rules,
        'is_public': t.is_public,
        'created_at': t.created_at.isoformat(),
    }


def tournament_team_to_dict(tt):
    return {
        'id': tt.id,
        'tournament_id': tt.tournament.id,
        'team_id': tt.team.id,
        'team_name': tt.team.name,
        'seed': tt.seed,
        'status': tt.status,
        'registered_by_id': tt.registered_by.id,
        'joined_at': tt.joined_at.isoformat(),
    }


def tournament_match_to_dict(m):
    return {
        'id': m.id,
        'tournament_id': m.tournament.id,
        'round_number': m.round_number,
        'match_number': m.match_number,
        'team1_id': m.team1.id if m.team1 else None,
        'team1_name': m.team1_name,
        'team1_seed': m.team1.seed if m.team1 else None,
        'team2_id': m.team2.id if m.team2 else None,
        'team2_name': m.team2_name,
        'team2_seed': m.team2.seed if m.team2 else None,
        'winner_id': m.winner.id if m.winner else None,
        'score1': m.score1,
        'score2': m.score2,
        'scheduled_time': m.scheduled_time.isoformat() if m.scheduled_time else None,
        'status': m.status,
        'bracket_position': m.bracket_position,
    }
