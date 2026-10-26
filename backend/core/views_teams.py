from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.db.models import Count
from django.db import transaction
from .models import Team, TeamMember, Notification, ChatMessage, TeamJoinRequest
from .entitlements import (
    can_create_team, can_join_team,
)
from .serializers import (
    err_msg as _err_msg, display_name,
)
from .validators import (
    SPORT_CHOICES, validate_string, validate_optional_string, validate_int, validate_enum, sanitize_text,
    validate_boolean,
)


from .view_shared import (
    _is_team_admin_or_owner,
)


@api_view(['POST'])
def leave_team(request):
    """
    Leave a team (non-owner only)
    Expected data: team_id
    """
    try:
        team_id = request.data.get('team_id')
        if not team_id:
            return Response({'error': 'Team ID is required'}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            team = Team.objects.select_for_update().get(id=team_id)

            if team.owner.id == request.user.id:
                return Response({'error': 'Team owner cannot leave. Delete the team instead.'}, status=status.HTTP_400_BAD_REQUEST)

            membership = TeamMember.objects.filter(team=team, user=request.user).first()
            if not membership:
                return Response({'error': 'You are not a member of this team'}, status=status.HTTP_400_BAD_REQUEST)

            membership.delete()

            # Update spots left
            team.spots_left = team.max_members - team.current_members
            team.save()

        # Notify team owner
        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        Notification.objects.create(
            user=team.owner,
            notification_type='team_left',
            title='Member Left',
            message=f'{user_name} left your team "{team.name}".',
            related_team=team,
        )

        return Response({'message': 'You have left the team'}, status=status.HTTP_200_OK)

    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Team Management ──



@api_view(['GET'])
def get_team_members(request, team_id):
    """
    Get all members of a team. Only for team owner/admin.
    """
    try:
        team = Team.objects.get(id=team_id)
        
        # Check if user is owner or admin
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can view members'}, status=status.HTTP_403_FORBIDDEN)
        
        members = TeamMember.objects.filter(team=team).select_related('user')
        
        data = []
        for m in members:
            user_name = f"{m.user.first_name} {m.user.last_name}".strip() or m.user.username
            member_info = {
                'id': m.id,
                'user_id': m.user.id,
                'user_name': user_name,
                'role': m.role,
                'joined_at': m.joined_at.isoformat(),
            }
            if request.user.id == m.user.id:
                member_info['email'] = m.user.email
            data.append(member_info)
        
        return Response({'members': data}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def remove_team_member(request):
    """
    Remove a member from team. Only for team owner.
    Expected: team_id, member_id
    """
    try:
        team_id = request.data.get('team_id')
        member_id = request.data.get('member_id')
        
        if not team_id or not member_id:
            return Response({'error': 'Team ID and Member ID are required'}, status=status.HTTP_400_BAD_REQUEST)
        
        team = Team.objects.get(id=team_id)
        
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can remove members'}, status=status.HTTP_403_FORBIDDEN)
        
        membership = TeamMember.objects.filter(id=member_id, team=team).first()
        if not membership:
            return Response({'error': 'Member not found'}, status=status.HTTP_404_NOT_FOUND)
        
        if membership.user.id == team.owner.id:
            return Response({'error': 'Cannot remove the owner'}, status=status.HTTP_400_BAD_REQUEST)
        
        member_name = f"{membership.user.first_name} {membership.user.last_name}".strip() or membership.user.username
        membership.delete()
        
        # Update spots left
        team.spots_left = team.max_members - team.current_members
        team.save()
        
        return Response({'message': f'{member_name} removed from team'}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def update_member_role(request):
    """
    Update member role (promote/demote). Only for team owner.
    Expected: team_id, member_id, role (owner/admin/member)
    """
    try:
        team_id = request.data.get('team_id')
        member_id = request.data.get('member_id')
        new_role = request.data.get('role')
        
        if not team_id or not member_id or not new_role:
            return Response({'error': 'Team ID, Member ID, and Role are required'}, status=status.HTTP_400_BAD_REQUEST)
        
        if new_role not in ['admin', 'member']:
            return Response({'error': 'Role must be admin or member'}, status=status.HTTP_400_BAD_REQUEST)
        
        team = Team.objects.get(id=team_id)
        
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can change roles'}, status=status.HTTP_403_FORBIDDEN)
        
        membership = TeamMember.objects.filter(id=member_id, team=team).first()
        if not membership:
            return Response({'error': 'Member not found'}, status=status.HTTP_404_NOT_FOUND)
        
        membership.role = new_role
        membership.save()
        
        return Response({'message': f'Role updated to {new_role}'}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Team Join Requests ──



@api_view(['GET'])
def get_team_join_requests(request, team_id):
    """
    Get pending join requests for a team. Only for team owner.
    """
    try:
        team = Team.objects.get(id=team_id)
        
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can view requests'}, status=status.HTTP_403_FORBIDDEN)
        
        requests = TeamJoinRequest.objects.filter(team=team, status='pending').select_related('user')
        
        data = []
        for req in requests:
            user_name = f"{req.user.first_name} {req.user.last_name}".strip() or req.user.username
            data.append({
                'id': req.id,
                'user_id': req.user.id,
                'user_name': user_name,
                'email': req.user.email,
                'requested_at': req.created_at.isoformat(),
            })
        
        return Response({'requests': data}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def handle_join_request(request):
    """
    Approve or reject a join request. Only for team owner.
    Expected: team_id, request_id, action (approve/reject)
    """
    try:
        team_id = request.data.get('team_id')
        request_id = request.data.get('request_id')
        action = request.data.get('action')
        
        if not team_id or not request_id or not action:
            return Response({'error': 'Team ID, Request ID, and Action are required'}, status=status.HTTP_400_BAD_REQUEST)
        
        if action not in ['approve', 'reject']:
            return Response({'error': 'Action must be approve or reject'}, status=status.HTTP_400_BAD_REQUEST)
        
        team = Team.objects.get(id=team_id)
        
        if not _is_team_admin_or_owner(team, request.user):
            return Response({'error': 'Only the team owner or admin can handle requests'}, status=status.HTTP_403_FORBIDDEN)
        
        join_request = TeamJoinRequest.objects.filter(id=request_id, team=team).first()
        if not join_request:
            return Response({'error': 'Request not found'}, status=status.HTTP_404_NOT_FOUND)
        
        if action == 'approve':
            if TeamMember.objects.filter(team=team, user=join_request.user).exists():
                return Response({'error': 'User is already a team member'}, status=status.HTTP_400_BAD_REQUEST)
            if team.spots_left <= 0:
                return Response({'error': 'This team is full'}, status=status.HTTP_400_BAD_REQUEST)

            # Add user as team member
            TeamMember.objects.create(
                team=team,
                user=join_request.user,
                role='member'
            )
            join_request.status = 'approved'
            join_request.save()

            # Recompute spots from the source of truth
            team.spots_left = max(0, team.max_members - team.current_members)
            team.save()
            
            # Notify user
            Notification.objects.create(
                user=join_request.user,
                notification_type='team_joined',
                title='Request Approved',
                message=f'Your request to join "{team.name}" has been approved!',
                related_team=team,
            )
            
            return Response({'message': 'Request approved, user added to team'}, status=status.HTTP_200_OK)
        else:
            join_request.status = 'rejected'
            join_request.save()
            
            Notification.objects.create(
                user=join_request.user,
                notification_type='general',
                title='Request Rejected',
                message=f'Your request to join "{team.name}" was rejected.',
                related_team=team,
            )
            
            return Response({'message': 'Request rejected'}, status=status.HTTP_200_OK)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def request_to_join_team(request):
    """
    Request to join a team (instead of instant join)
    """
    try:
        team_id = request.data.get('team_id')
        
        if not team_id:
            return Response({'error': 'Team ID is required'}, status=status.HTTP_400_BAD_REQUEST)
        
        team = Team.objects.get(id=team_id)
        
        # Check if already a member
        existing = TeamMember.objects.filter(team=team, user=request.user).first()
        if existing:
            return Response({'error': 'You are already a member of this team'}, status=status.HTTP_400_BAD_REQUEST)

        if not can_join_team(request.user):
            return Response({
                'error': 'Free accounts can join 1 team. Upgrade to Premium to join more.',
                'upgrade_required': True,
            }, status=status.HTTP_402_PAYMENT_REQUIRED)

        # Check if already requested
        existing_request = TeamJoinRequest.objects.filter(team=team, user=request.user, status='pending').first()
        if existing_request:
            return Response({'error': 'You already have a pending request'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Create request
        TeamJoinRequest.objects.create(
            team=team,
            user=request.user,
            status='pending'
        )
        
        # Notify owner
        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        Notification.objects.create(
            user=team.owner,
            notification_type='general',
            title='New Join Request',
            message=f'{user_name} requested to join your team "{team.name}".',
            related_team=team,
        )
        
        return Response({'message': 'Join request sent'}, status=status.HTTP_201_CREATED)
    
    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ── Feature 3: Match History ──



@api_view(['POST'])
def create_team(request):
    """
    Create a new team
    Expected data: name, sport, description, location, max_members, is_seeking_players
    """
    try:
        try:
            name = validate_string(request.data.get('name'), 100, 'Team name')
            sport = validate_enum(request.data.get('sport', 'other'), SPORT_CHOICES, 'Sport')
            description = sanitize_text(validate_optional_string(request.data.get('description', ''), 5000, 'Description'))
            location = validate_optional_string(request.data.get('location', ''), 200, 'Location')
            max_members = validate_int(request.data.get('max_members', 10), 2, 100, 'Max members')
            is_seeking_players = validate_boolean(request.data.get('is_seeking_players', False), 'is_seeking_players')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        if not can_create_team(request.user):
            return Response({
                'error': 'Free accounts can create 1 team. Upgrade to Premium for unlimited teams.',
                'upgrade_required': True,
            }, status=status.HTTP_402_PAYMENT_REQUIRED)

        team = Team.objects.create(
            name=name,
            sport=sport,
            owner=request.user,
            description=description,
            location=location,
            max_members=max_members,
            is_seeking_players=is_seeking_players,
            spots_left=max_members - 1  # Owner is already a member
        )

        # Add owner as member
        TeamMember.objects.create(
            team=team,
            user=request.user,
            role='owner'
        )

        return Response({
            'message': 'Team created successfully',
            'team': {
                'id': team.id,
                'name': team.name,
                'sport': team.sport,
                'description': team.description,
                'location': team.location,
                'max_members': team.max_members,
                'current_members': team.current_members,
                'is_active': team.is_active,
                'is_seeking_players': team.is_seeking_players,
                'spots_left': team.spots_left,
                'owner_id': team.owner.id,
                'owner_name': display_name(team.owner),
                'created_at': team.created_at.isoformat(),
                'updated_at': team.updated_at.isoformat(),
            }
        }, status=status.HTTP_201_CREATED)

    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )




@api_view(['GET'])
def get_my_teams(request):
    """
    Get all teams the user belongs to
    """
    try:
        memberships = TeamMember.objects.filter(user=request.user).select_related('team', 'team__owner').annotate(
            member_count=Count('team__members')
        )
        
        teams = []
        for membership in memberships:
            team = membership.team
            teams.append({
                'id': team.id,
                'name': team.name,
                'sport': team.sport,
                'description': team.description,
                'type': f"{team.sport.title()} {team.max_members}v{team.max_members}",
                'location': team.location,
                'max_members': team.max_members,
                'current_members': membership.member_count,
                'spots_left': max(0, team.max_members - membership.member_count),
                'owner_id': team.owner.id,
                'owner_name': display_name(team.owner),
                'created_at': team.created_at.isoformat(),
                'updated_at': team.updated_at.isoformat(),
                'is_active': team.is_active,
                'status': 'Active' if team.is_active else 'Inactive',
                'is_owner': team.owner.id == request.user.id,
                'role': membership.role,
            })

        return Response({
            'teams': teams
        }, status=status.HTTP_200_OK)

    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )




@api_view(['GET'])
@permission_classes([AllowAny])
def get_teams_seeking_players(request):
    """
    Get all teams that are seeking players
    """
    try:
        teams = Team.objects.filter(
            is_seeking_players=True,
            is_active=True
        ).select_related('owner').annotate(member_count=Count('members'))

        teams_data = []
        for team in teams:
            teams_data.append({
                'id': team.id,
                'name': team.name,
                'sport': team.sport,
                'description': team.description,
                'type': f"{team.sport.title()} {team.max_members}v{team.max_members}",
                'location': team.location,
                'max_members': team.max_members,
                'current_members': team.member_count,
                'spots_left': max(0, team.max_members - team.member_count),
                'owner_id': team.owner.id,
                'owner_name': display_name(team.owner),
                'created_at': team.created_at.isoformat(),
                'updated_at': team.updated_at.isoformat(),
            })

        return Response({
            'teams': teams_data
        }, status=status.HTTP_200_OK)

    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )




@api_view(['POST'])
def join_team(request):
    """
    Join a team
    Expected data: team_id
    """
    try:
        team_id = request.data.get('team_id')
        
        if not team_id:
            return Response(
                {'error': 'Team ID is required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        with transaction.atomic():
            team = Team.objects.select_for_update().get(id=team_id)
            
            # Check if already a member
            if TeamMember.objects.filter(team=team, user=request.user).exists():
                return Response(
                    {'error': 'You are already a member of this team'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if not can_join_team(request.user):
                return Response({
                    'error': 'Free accounts can join 1 team. Upgrade to Premium to join more.',
                    'upgrade_required': True,
                }, status=status.HTTP_402_PAYMENT_REQUIRED)

            # Check if spots available (atomic)
            if team.spots_left <= 0:
                return Response(
                    {'error': 'This team is full'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Add user as member
            TeamMember.objects.create(
                team=team,
                user=request.user,
                role='member'
            )

            # Update spots left
            team.spots_left = team.max_members - team.current_members
            team.save()

        # Notify team owner
        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        Notification.objects.create(
            user=team.owner,
            notification_type='team_joined',
            title='New Member',
            message=f'{user_name} joined your team "{team.name}".',
            related_team=team,
        )

        return Response({
            'message': 'Successfully joined the team',
            'team': {
                'id': team.id,
                'name': team.name,
            }
        }, status=status.HTTP_200_OK)

    except Team.DoesNotExist:
        return Response(
            {'error': 'Team not found'},
            status=status.HTTP_404_NOT_FOUND
        )
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


# Match Endpoints



@api_view(['GET'])
def get_team_chat(request, team_id):
    """
    Get chat messages for a team. Only team members can view.
    """
    try:
        team = Team.objects.get(id=team_id)

        is_member = TeamMember.objects.filter(team=team, user=request.user).exists()
        is_owner = team.owner.id == request.user.id

        if not is_member and not is_owner:
            return Response(
                {'error': 'You are not a member of this team'},
                status=status.HTTP_403_FORBIDDEN
            )

        messages = list(
            ChatMessage.objects.filter(team=team).select_related('user')
            .order_by('-created_at', '-id')[:100]
        )
        messages.reverse()

        data = []
        for m in messages:
            user_name = f"{m.user.first_name} {m.user.last_name}".strip() or m.user.username
            data.append({
                'id': m.id,
                'user_id': m.user.id,
                'user_name': user_name,
                'message': m.message,
                'created_at': m.created_at.isoformat(),
            })

        return Response({'messages': data}, status=status.HTTP_200_OK)

    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)




@api_view(['POST'])
def send_team_chat(request, team_id):
    """
    Send a chat message to a team. Only team members can send.
    """
    try:
        team = Team.objects.get(id=team_id)
        try:
            raw_message = request.data.get('message', '')
            message_text = sanitize_text(validate_string(raw_message, 10000, 'Message'))
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)

        is_member = TeamMember.objects.filter(team=team, user=request.user).exists()
        is_owner = team.owner.id == request.user.id

        if not is_member and not is_owner:
            return Response(
                {'error': 'You are not a member of this team'},
                status=status.HTTP_403_FORBIDDEN
            )

        chat_message = ChatMessage.objects.create(
            team=team,
            user=request.user,
            message=message_text
        )

        user_name = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username

        # Notify all other team members (single bulk insert)
        other_members = TeamMember.objects.filter(team=team).exclude(user=request.user).values_list('user_id', flat=True)
        notified = set(other_members)
        if team.owner.id != request.user.id:
            notified.add(team.owner.id)
        Notification.objects.bulk_create([
            Notification(
                user_id=uid,
                notification_type='team_chat_message',
                title=f'New message in {team.name}',
                message=f'{user_name}: {message_text[:100]}',
                related_team=team,
            )
            for uid in notified
        ])

        return Response({
            'message': 'Message sent',
            'chat_message': {
                'id': chat_message.id,
                'user_id': request.user.id,
                'user_name': user_name,
                'message': message_text,
                'created_at': chat_message.created_at.isoformat(),
            }
        }, status=status.HTTP_201_CREATED)

    except Team.DoesNotExist:
        return Response({'error': 'Team not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
