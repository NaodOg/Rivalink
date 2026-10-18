from django.utils import timezone
from datetime import datetime, timedelta, time
from .models import (
    UserProfile, Team, TeamMember, MatchParticipant, VenueBooking, TournamentMatch,
    UserSportRating, TeamRanking, Follow,
)
from .elo import update_elo_with_matches
from .entitlements import (
    is_premium,
)
from .monetization import (
    BOOKING_SLOT_HOURS,
)
from .serializers import (
    display_name,
)



# ── Shared helpers ──

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


# ── Trust & safety ──



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
