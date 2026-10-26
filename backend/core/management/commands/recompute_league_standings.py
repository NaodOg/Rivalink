"""Recompute league standings from completed fixtures.

Useful as a repair tool if standings ever drift from the fixture results:
    python manage.py recompute_league_standings
"""
from django.core.management.base import BaseCommand
from django.db import transaction

from core.models import League, LeagueMember
from core.view_shared import _league_delta


class Command(BaseCommand):
    help = 'Rebuild LeagueMember standings from completed fixtures.'

    def handle(self, *args, **options):
        league_ids = set(
            LeagueMember.objects.values_list('league_id', flat=True)
        ) | set(
            League.objects.filter(fixtures__isnull=False).values_list('id', flat=True)
        )
        updated = 0

        for league in League.objects.filter(id__in=league_ids).select_related('organizer'):
            with transaction.atomic():
                stats = {}
                fixtures = league.fixtures.filter(status='completed').select_related('home_team', 'away_team')
                team_ids = set()
                for fixture in fixtures:
                    team_ids.add(fixture.home_team_id)
                    team_ids.add(fixture.away_team_id)
                    for team_id, gf, ga in (
                        (fixture.home_team_id, fixture.home_score, fixture.away_score),
                        (fixture.away_team_id, fixture.away_score, fixture.home_score),
                    ):
                        member = stats.setdefault(team_id, LeagueMember(team_id=team_id))
                        _league_delta(member, gf, ga, league, +1)

                members = []
                for team_id, member in stats.items():
                    member.league = league
                    members.append(member)
                if not members:
                    continue
                for member in members:
                    member.wins = member.wins or 0
                    member.losses = member.losses or 0
                    member.draws = member.draws or 0
                    member.points = member.points or 0
                    member.goals_for = member.goals_for or 0
                    member.goals_against = member.goals_against or 0
                    member.matches_played = member.matches_played or 0
                member_ids = [m.team_id for m in members]
                LeagueMember.objects.filter(league=league).exclude(team_id__in=member_ids).update(
                    wins=0, losses=0, draws=0, points=0,
                    goals_for=0, goals_against=0, matches_played=0)
                for member in members:
                    existing = LeagueMember.objects.filter(league=league, team_id=member.team_id).first()
                    if existing:
                        existing.wins = member.wins
                        existing.losses = member.losses
                        existing.draws = member.draws
                        existing.points = member.points
                        existing.goals_for = member.goals_for
                        existing.goals_against = member.goals_against
                        existing.matches_played = member.matches_played
                        existing.save()
                    else:
                        LeagueMember.objects.create(
                            league=league, team_id=member.team_id,
                            wins=member.wins, losses=member.losses, draws=member.draws,
                            points=member.points, goals_for=member.goals_for,
                            goals_against=member.goals_against,
                            matches_played=member.matches_played)
                updated += 1

        self.stdout.write(self.style.SUCCESS(f'Recomputed standings for {updated} league(s).'))
