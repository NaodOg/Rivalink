from django.utils import timezone
from django.contrib.auth.models import User
from datetime import datetime, timedelta, time
from .models import (
    UserProfile, TeamMember, MatchParticipant, VenueBooking, TournamentMatch,
    UserSportRating, TeamRanking, Follow, LeagueMember, LeagueFixture,
)
from .glicko2 import display_rating, update_rating
from .monetization import (
    BOOKING_SLOT_HOURS,
)
from .push import notify
from .serializers import (
    display_name,
)



# â”€â”€ Shared helpers â”€â”€

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




def _is_team_admin_or_owner(team, user):
    if team.owner.id == user.id:
        return True
    return TeamMember.objects.filter(team=team, user=user, role='admin').exists()




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

    for p in participants:
        rating_for(p.user)

    winning_group = result.winning_group
    if winning_group not in ('A', 'B'):
        winning_group = ''

    is_draw = winning_group == '' or result.result_type == 'draw'

    now = timezone.now()
    snapshots = {
        uid: (r.elo_rating, r.rating_deviation, r.volatility, r.matches_played)
        for uid, r in ratings.items()
    }
    changed = []
    for group_name, group in teams.items():
        opponents = teams['B'] if group_name == 'A' else teams['A']
        if is_draw:
            score = 0.5
        elif group_name == winning_group:
            score = 1.0
        else:
            score = 0.0
        opponent_rows = [
            (snapshots[p.user_id][0], snapshots[p.user_id][1], score)
            for p in opponents
        ]
        for p in group:
            r = ratings[p.user_id]
            old_rating, old_rd, old_vol, _ = snapshots[p.user_id]
            new_rating, new_rd, new_vol = update_rating(
                old_rating, old_rd, old_vol, opponent_rows)
            r.elo_rating = display_rating(new_rating)
            r.rating_deviation = new_rd
            r.volatility = new_vol
            r.last_rated_at = now
            if is_draw:
                r.draws += 1
            elif group_name == winning_group:
                r.wins += 1
            else:
                r.losses += 1
            r.matches_played += 1
            changed.append(r)

    if changed:
        UserSportRating.objects.bulk_update(
            changed,
            ['elo_rating', 'rating_deviation', 'volatility', 'last_rated_at',
             'matches_played', 'wins', 'losses', 'draws'],
        )




def _apply_result_rankings(match, result):
    """Apply Elo + team standings once a result is confirmed. Idempotent."""
    if result.rankings_applied:
        return

    sport = match.sport
    participants = list(MatchParticipant.objects.filter(match=match).select_related('user'))

    _update_team_sport_individual_elo(match, sport, result)

    if result.match_type == 'team_vs_team':
        _apply_team_rankings(match, result, sport)
    elif not MatchParticipant.objects.filter(match=match).exclude(team_group='').exists():
        # Group-based (A/B) results already got their Elo above; don't double-apply.
        _apply_individual_elo(participants, result, sport)

    # No-shows are recorded when the result is confirmed.
    for uid in result.no_show_list:
        try:
            profile = UserProfile.get_or_create_for_user(User.objects.get(id=uid))
        except User.DoesNotExist:
            continue
        profile.no_show_count += 1
        profile.save(update_fields=['no_show_count'])

    result.rankings_applied = True
    result.save(update_fields=['rankings_applied'])

    # A confirmed result for a fixture-linked match updates league standings.
    fixture = LeagueFixture.objects.filter(match=match).first()
    if fixture and fixture.league.status == 'live':
        scores = _scores_for_result(result, fixture)
        if scores:
            _apply_fixture_result(fixture, scores[0], scores[1])


def _apply_individual_elo(participants, result, sport):
    """Glicko-2 for pickup matches with any number of players (2..N)."""
    if len(participants) < 2:
        return

    ratings = {}
    for p in participants:
        r, _ = UserSportRating.objects.get_or_create(user=p.user, sport=sport)
        ratings[p.user_id] = r
    ids = list(ratings.keys())

    is_draw = result.result_type == 'draw' or not result.winner_user_id

    now = timezone.now()
    snapshots = {
        uid: (r.elo_rating, r.rating_deviation, r.volatility)
        for uid, r in ratings.items()
    }
    changed = []

    if is_draw:
        for uid in ids:
            r = ratings[uid]
            old_rating, old_rd, old_vol = snapshots[uid]
            opponents = [
                (snapshots[other][0], snapshots[other][1], 0.5)
                for other in ids if other != uid
            ]
            new_rating, new_rd, new_vol = update_rating(
                old_rating, old_rd, old_vol, opponents)
            r.elo_rating = display_rating(new_rating)
            r.rating_deviation = new_rd
            r.volatility = new_vol
            r.last_rated_at = now
            r.matches_played += 1
            r.draws += 1
            changed.append(r)
    else:
        winner_id = result.winner_user_id
        if winner_id not in ratings:
            return
        loser_ids = [uid for uid in ids if uid != winner_id]

        for uid in loser_ids:
            r = ratings[uid]
            old_rating, old_rd, old_vol = snapshots[uid]
            opponents = [(snapshots[winner_id][0], snapshots[winner_id][1], 0.0)]
            new_rating, new_rd, new_vol = update_rating(
                old_rating, old_rd, old_vol, opponents)
            r.elo_rating = display_rating(new_rating)
            r.rating_deviation = new_rd
            r.volatility = new_vol
            r.last_rated_at = now
            r.matches_played += 1
            r.losses += 1
            changed.append(r)

        wr = ratings[winner_id]
        old_rating, old_rd, old_vol = snapshots[winner_id]
        opponents = [
            (snapshots[uid][0], snapshots[uid][1], 1.0) for uid in loser_ids
        ]
        new_rating, new_rd, new_vol = update_rating(
            old_rating, old_rd, old_vol, opponents)
        wr.elo_rating = display_rating(new_rating)
        wr.rating_deviation = new_rd
        wr.volatility = new_vol
        wr.last_rated_at = now
        wr.matches_played += 1
        wr.wins += 1
        changed.append(wr)

    if changed:
        UserSportRating.objects.bulk_update(
            changed,
            ['elo_rating', 'rating_deviation', 'volatility', 'last_rated_at',
             'matches_played', 'wins', 'losses', 'draws'],
        )


def _apply_team_rankings(match, result, sport):
    """Team standings. Uses explicit team1/team2 when provided."""
    team1 = result.team1 or match.team
    team2 = result.team2

    if not team2 and match.team:
        # Fallback: infer the opponent from participants' team memberships.
        others = MatchParticipant.objects.filter(match=match).exclude(
            user__in=match.team.members.all())
        for mp in others:
            tm = TeamMember.objects.filter(user=mp.user).exclude(team=match.team).first()
            if tm:
                team2 = tm.team
                break

    if not team1 or not team2:
        return

    r1, _ = TeamRanking.objects.get_or_create(team=team1, sport=sport)
    r2, _ = TeamRanking.objects.get_or_create(team=team2, sport=sport)

    if result.result_type == 'draw':
        r1.draws += 1
        r1.points += 1
        r1.matches_played += 1
        r2.draws += 1
        r2.points += 1
        r2.matches_played += 1
        r1.save()
        r2.save()
        return

    if not result.winner_team_id:
        return

    if result.winner_team_id == team1.id:
        w_rank, l_rank = r1, r2
    elif result.winner_team_id == team2.id:
        w_rank, l_rank = r2, r1
    else:
        return

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


# â”€â”€ League fixtures & standings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

def _league_delta(member, team_score, opp_score, league, sign):
    if team_score > opp_score:
        member.wins += sign
        member.points += sign * league.points_win
    elif team_score == opp_score:
        member.draws += sign
        member.points += sign * league.points_draw
    else:
        member.losses += sign
    member.goals_for += sign * team_score
    member.goals_against += sign * opp_score
    member.matches_played += sign


def _apply_fixture_standing_delta(fixture, home_score, away_score, sign):
    league = fixture.league
    home, _ = LeagueMember.objects.get_or_create(league=league, team=fixture.home_team)
    away, _ = LeagueMember.objects.get_or_create(league=league, team=fixture.away_team)
    _league_delta(home, home_score, away_score, league, sign)
    _league_delta(away, away_score, home_score, league, sign)
    home.save()
    away.save()


def _apply_fixture_result(fixture, home_score, away_score, walkover=False):
    """Apply (or correct) a fixture score to the standings and check completion."""
    league = fixture.league
    before = {m.team_id: idx + 1 for idx, m in enumerate(league_standings(league))}
    if (fixture.status == 'completed'
            and fixture.home_score is not None and fixture.away_score is not None):
        _apply_fixture_standing_delta(fixture, fixture.home_score, fixture.away_score, -1)
    _apply_fixture_standing_delta(fixture, home_score, away_score, +1)
    fixture.home_score = home_score
    fixture.away_score = away_score
    fixture.is_walkover = walkover
    fixture.status = 'completed'
    fixture.save(update_fields=['home_score', 'away_score', 'is_walkover', 'status'])

    # Remember the rank before this result so the table can show movement arrows.
    for idx, member in enumerate(league_standings(league), start=1):
        member.prev_rank = before.get(member.team_id, 0)
        member.save(update_fields=['prev_rank'])

    _check_league_complete(fixture.league)
    return fixture


def league_standings(league):
    """Members sorted by points -> goal difference -> goals for."""
    members = list(LeagueMember.objects.filter(league=league).select_related('team'))
    members.sort(key=lambda m: (-m.points, -m.goal_difference, -m.goals_for, m.team.name))
    return members


def _check_league_complete(league):
    if league.status != 'live':
        return
    fixtures = league.fixtures.all()
    if not fixtures.exists() or fixtures.filter(status='scheduled').exists():
        return
    members = league_standings(league)
    if not members:
        return
    champion = members[0].team
    league.status = 'completed'
    league.is_active = False
    league.champion = champion
    league.save(update_fields=['status', 'is_active', 'champion'])
    notify(league.organizer, 'general', 'League complete',
           f'"{league.name}" has finished. Champion: {champion.name}.')
    for index, member in enumerate(members, start=1):
        owner = member.team.owner
        if owner.id != league.organizer_id:
            notify(owner, 'general', 'League complete',
                   f'"{league.name}" finished â€” final place: {index}.')


def _scores_for_result(result, fixture):
    """Map a confirmed MatchResult (winner-first score) onto fixture home/away."""
    if not result.score or ' - ' not in result.score:
        return None
    try:
        a, b = (int(x.strip()) for x in result.score.split(' - ', 1))
    except (ValueError, TypeError):
        return None
    if result.result_type == 'draw':
        return (a, b)
    hi, lo = max(a, b), min(a, b)
    if result.winner_team_id == fixture.home_team_id:
        return (hi, lo)
    if result.winner_team_id == fixture.away_team_id:
        return (lo, hi)
    return None


def _generate_round_robin(league):
    """Create the fixture schedule (single or double round robin)."""
    teams = [m.team for m in LeagueMember.objects.filter(league=league).select_related('team')]
    if len(teams) < 2:
        return []
    slots = list(teams)
    if len(slots) % 2:
        slots.append(None)
    n = len(slots)
    rounds = []
    for _ in range(n - 1):
        pairs = []
        for i in range(n // 2):
            a, b = slots[i], slots[n - 1 - i]
            if a is not None and b is not None:
                pairs.append((a, b))
        rounds.append(pairs)
        slots = [slots[0]] + [slots[-1]] + slots[1:-1]
    if league.double_round_robin:
        rounds += [[(away, home) for home, away in pairs] for pairs in list(rounds)]

    fixtures = []
    for round_number, pairs in enumerate(rounds, start=1):
        kickoff = league.start_date + timedelta(weeks=round_number - 1)
        for index, (home, away) in enumerate(pairs):
            fixtures.append(LeagueFixture(
                league=league,
                round_number=round_number,
                home_team=home,
                away_team=away,
                kickoff=kickoff + timedelta(hours=index),
            ))
    LeagueFixture.objects.bulk_create(fixtures)
    return fixtures


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
            TournamentMatch.objects.create(
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
            status__in=['pending', 'reserved', 'confirmed']
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
    slot_delta = timedelta(hours=BOOKING_SLOT_HOURS)
    while cursor + slot_delta <= day_end and len(slots) < max_slots:
        slot_start = cursor
        slot_end = cursor + slot_delta

        if target_date == timezone.localdate() and slot_start <= now:
            cursor += slot_delta
            continue

        overlaps = any(slot_start < end and slot_end > start for start, end in blocked)
        if not overlaps:
            slots.append({
                'start_time': slot_start.strftime('%H:%M'),
                'end_time': slot_end.strftime('%H:%M'),
                'label': f"{slot_start.strftime('%H:%M')} - {slot_end.strftime('%H:%M')}",
            })

        cursor += slot_delta

    return slots


# â”€â”€ Trust & safety â”€â”€



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

