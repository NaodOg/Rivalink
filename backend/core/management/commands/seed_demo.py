"""Seed demo data for VYRO/VYRO so the app has something to show.

Idempotent-ish: objects are looked up by name and reused. Safe to run twice.
    python manage.py seed_demo
"""
from datetime import timedelta

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand
from django.utils import timezone

from core.models import (
    UserProfile, Team, TeamMember, Match, MatchParticipant, MatchResult,
    League, LeagueMember, Tournament, TournamentTeam, TournamentMatch,
    Venue, VenueBooking, Referee, RefereeBooking, Notification,
    UserSportRating, TeamRanking,
)
from core.views import _generate_bracket, _advance_winner, _check_tournament_complete


class Command(BaseCommand):
    help = 'Seed demo data (users, teams, matches, leagues, tournaments, venues, referees).'

    def _user(self, email, first, last=''):
        u, created = User.objects.get_or_create(
            username=email, defaults={'email': email, 'first_name': first, 'last_name': last})
        if created:
            u.set_password('Test1234')
            u.save()
        UserProfile.get_or_create_for_user(u)
        return u

    def handle(self, *args, **options):
        now = timezone.now()
        me = User.objects.filter(email='naodog00@gmail.com').first() or self._user('demo@vyro.app', 'Naod')
        UserProfile.get_or_create_for_user(me)

        names = [('Abe', 'K'), ('Sara', 'T'), ('Dawit', 'M'), ('Hana', 'G'),
                 ('Yonas', 'B'), ('Liya', 'A'), ('Kebede', 'W'), ('Marta', 'D')]
        players = [self._user(f'demo{i}@vyro.app', f, l) for i, (f, l) in enumerate(names, 1)]

        # ── Teams ──
        team_names = ['Unity FC', 'Bole Ballers', 'CMC United', 'Sarbet Stars',
                      'Meskel Rangers', 'Addis Titans', 'Entoto FC', 'Friendship XI']
        teams = []
        for i, tname in enumerate(team_names):
            t, _ = Team.objects.get_or_create(
                name=tname,
                defaults={'sport': 'soccer', 'owner': players[i % len(players)],
                          'location': 'Addis Ababa', 'max_members': 12, 'spots_left': 3,
                          'is_seeking_players': True})
            TeamMember.objects.get_or_create(team=t, user=t.owner, defaults={'role': 'owner'})
            for p in players[i % len(players):][:3]:
                TeamMember.objects.get_or_create(team=t, user=p, defaults={'role': 'member'})
            teams.append(t)

        # ── Matches (upcoming, so Home/Explore have cards) ──
        sports = ['soccer', 'basketball', 'tennis', 'volleyball']
        locations = ['Bole', 'CMC', 'Sarbet', 'Piassa', 'Kazanchis']
        skills = ['any', 'beginner', 'intermediate', 'advanced']
        for i in range(8):
            title = f'Pickup {sports[i % len(sports)].title()} #{i + 1}'
            m, _ = Match.objects.get_or_create(
                title=title,
                defaults={
                    'sport': sports[i % len(sports)],
                    'description': 'Friendly game — bring a light and dark shirt.',
                    'location': locations[i % len(locations)],
                    'date_time': now + timedelta(hours=6 + i * 6),
                    'max_players': [10, 8, 4, 12][i % 4],
                    'current_players': [3, 6, 1, 9][i % 4],
                    'price': [0, 150, 100, 200, 250][i % 5],
                    'skill_level': skills[i % len(skills)],
                    'organizer': me if i % 2 == 0 else players[i % len(players)],
                    'is_active': True,
                })
            MatchParticipant.objects.get_or_create(match=m, user=m.organizer)
            for p in players[: (i % 4) + 1]:
                MatchParticipant.objects.get_or_create(match=m, user=p)

        # ── Past matches with results + Elo + team rankings ──
        for i in range(4):
            m, _ = Match.objects.get_or_create(
                title=f'Completed Match #{i + 1}',
                defaults={
                    'sport': 'soccer', 'location': locations[i % len(locations)],
                    'date_time': now - timedelta(days=i + 1), 'max_players': 10,
                    'current_players': 2, 'price': 0, 'organizer': me, 'is_active': True,
                })
            MatchParticipant.objects.get_or_create(match=m, user=me)
            MatchParticipant.objects.get_or_create(match=m, user=players[i % len(players)])
            MatchResult.objects.get_or_create(
                match=m,
                defaults={'match_type': 'pickup', 'result_type': 'individual',
                          'winner_user_id': me.id, 'mvp_user_id': me.id,
                          'score': '3 - 2', 'created_by': me})

        for p in [me] + players:
            UserSportRating.objects.get_or_create(user=p, sport='soccer', defaults={'elo_rating': 1200})
        for t in teams:
            TeamRanking.objects.get_or_create(
                team=t, sport='soccer',
                defaults={'wins': 2, 'points': 6, 'goals_for': 7, 'goals_against': 4, 'matches_played': 2})

        # ── League ──
        league, created = League.objects.get_or_create(
            name='Addis Premier League',
            defaults={'sport': 'soccer', 'format': '5v5', 'max_teams': 8,
                      'current_teams': min(6, len(teams)), 'entry_fee': 500,
                      'prize': 'Br 10,000 + Trophy', 'start_date': now + timedelta(days=14),
                      'location': 'Addis Ababa', 'organizer': me})
        if created:
            for i, t in enumerate(teams[:6]):
                LeagueMember.objects.create(
                    league=league, team=t, wins=4 - i, losses=i, draws=1,
                    points=(4 - i) * 3 + 1, goals_for=12 - i, goals_against=4 + i,
                    matches_played=5)

        # ── Tournament with a real bracket ──
        tournament, created = Tournament.objects.get_or_create(
            name='VYRO Champions Cup',
            defaults={'sport': 'soccer', 'format': 'single_elimination', 'max_teams': 8,
                      'current_teams': 8, 'entry_fee': 1000, 'prize_pool': '1st Br 20,000 · 2nd Br 8,000',
                      'rounds': 3, 'status': 'live', 'start_date': now + timedelta(days=3),
                      'organizer': me, 'location': 'Addis Ababa', 'is_public': True,
                      'rules': 'Group stage none · straight knockout · 20 min halves.'})
        if created:
            for i, t in enumerate(teams):
                TournamentTeam.objects.create(
                    tournament=tournament, team=t, seed=i + 1, registered_by=me)
            _generate_bracket(tournament)

            # play out round 1 so the bracket is filled
            for m in TournamentMatch.objects.filter(tournament=tournament, round_number=1):
                if m.team1 and m.team2 and m.status != 'completed':
                    m.score1, m.score2 = 3, 1
                    m.winner, m.status = m.team1, 'completed'
                    m.save()
                    if m.team2:
                        m.team2.status = 'eliminated'
                        m.team2.save()
                    m.team1.status = 'active'
                    m.team1.save()
                    _advance_winner(m)
            _check_tournament_complete(tournament)

        # ── Venues + bookings (for the owner dashboard) ──
        venue_specs = [
            ('Bole Turf Arena', 'Bole', 'soccer', 1500, 40),
            ('CMC Sports Park', 'CMC', 'multiple', 1200, 60),
        ]
        for vname, city, sport, price, cap in venue_specs:
            v, created = Venue.objects.get_or_create(
                name=vname,
                defaults={'owner': me, 'city': city, 'address': f'{city} Road',
                          'description': 'Floodlit pitch with changing rooms.',
                          'sports': sport, 'price_per_hour': price, 'capacity': cap,
                          'amenities': 'Parking, Floodlights, Locker rooms',
                          'opening_time': '06:00', 'closing_time': '22:00',
                          'is_available': True, 'verification_status': 'verified',
                          'average_rating': 4.6})
            if created:
                for i, status in enumerate(['pending', 'confirmed', 'completed']):
                    VenueBooking.objects.create(
                        venue=v, booked_by=players[i], date=(now + timedelta(days=i + 1)).date(),
                        start_time='18:00', end_time='19:00', hours=1,
                        total_price=price, status=status)

        # ── Referees + a booking ──
        for i, s in enumerate(['soccer', 'basketball']):
            ru = self._user(f'ref{i}@vyro.app', 'Ref', f'#{i + 1}')
            ref, _ = Referee.objects.get_or_create(
                user=ru,
                defaults={'sports': s, 'experience_years': 5 + i, 'certification': 'National',
                          'bio': 'Certified match official.', 'hourly_rate': 300,
                          'location': 'Addis Ababa', 'is_available': True,
                          'verification_status': 'verified', 'average_rating': 4.8,
                          'total_matches': 20 + i})
            match = Match.objects.filter(organizer=me).first()
            if match:
                RefereeBooking.objects.get_or_create(
                    referee=ref, match=match,
                    defaults={'booked_by': me, 'status': 'pending', 'fee': ref.hourly_rate})

        # ── Notifications ──
        for i in range(3):
            Notification.objects.get_or_create(
                user=me, title=f'Welcome bonus #{i + 1}',
                defaults={'notification_type': 'general',
                          'message': 'Your demo data is ready. Explore leagues, brackets and venues!'})

        self.stdout.write(self.style.SUCCESS(
            'Seed complete: '
            f'{Team.objects.count()} teams · {Match.objects.count()} matches · '
            f'{Tournament.objects.count()} tournaments · {Venue.objects.count()} venues · '
            f'{Referee.objects.count()} referees.'))
