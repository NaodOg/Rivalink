from django.utils import timezone

from .models import UserProfile, Match, Team, TeamMember

MAX_FREE_MONTHLY_HOSTS = 2
MAX_FREE_TEAMS_CREATED = 1
MAX_FREE_TEAMS_JOINED = 1


def is_premium(user):
    """True when the user has an active (non-expired) premium subscription."""
    if not user or not getattr(user, 'is_authenticated', False):
        return False
    return UserProfile.get_or_create_for_user(user).premium_active


def can_host_match(user):
    if is_premium(user):
        return True
    month_start = timezone.now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    count = Match.objects.filter(organizer=user, created_at__gte=month_start).count()
    return count < MAX_FREE_MONTHLY_HOSTS


def can_create_team(user):
    if is_premium(user):
        return True
    return Team.objects.filter(owner=user).count() < MAX_FREE_TEAMS_CREATED


def can_join_team(user):
    if is_premium(user):
        return True
    return TeamMember.objects.filter(user=user).count() < MAX_FREE_TEAMS_JOINED


def team_all_premium(team):
    """Strict league rule: every team member (incl. owner) must be premium."""
    members = TeamMember.objects.filter(team=team).select_related('user')
    if team.owner_id and not TeamMember.objects.filter(team=team, user=team.owner).exists():
        return is_premium(team.owner)
    for member in members:
        if not UserProfile.get_or_create_for_user(member.user).premium_active:
            return False
    return True


PREMIUM_REQUIRED_RESPONSE = {
    'error': 'This feature requires VYRO Premium',
    'upgrade_required': True,
}
