from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.authtoken.models import Token
from django.contrib.auth.models import User
from django.contrib.auth import authenticate
from django.db import IntegrityError
from django.conf import settings
from .models import UserProfile, Referral
from .audit import log_event
from .serializers import (
    err_msg as _err_msg,
)
from .validators import (
    AuthRateThrottle, validate_email, validate_phone, validate_string, validate_optional_string, sanitize_text,
    validate_password, validate_image,
)


from .view_shared import (
    _user_payload,
)


@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    return Response({
        "status": "ok",
        "message": "Rivalink backend connected successfully"
    })



@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def signup(request):
    """
    User registration endpoint
    Expected data: name, phone, email, password
    """
    try:
        try:
            name = validate_string(request.data.get('name'), 100, 'Name')
            phone = validate_phone(request.data.get('phone'))
            email = validate_email(request.data.get('email'))
            password = validate_password(request.data.get('password'))
            location = validate_optional_string(request.data.get('location', ''), 200, 'Location')
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if user already exists (generic error — no email enumeration)
        if User.objects.filter(username=email).exists():
            log_event(request, 'signup', None, 'duplicate_email')
            return Response(
                {'error': 'Sign up failed. Please try logging in instead.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Create user
        user = User.objects.create_user(
            username=email,
            email=email,
            password=password,
            first_name=name.split()[0] if name else '',
            last_name=' '.join(name.split()[1:]) if len(name.split()) > 1 else ''
        )
        
        # Create user profile with phone and location
        UserProfile.objects.create(user=user, phone=phone, location=location)
        UserProfile.get_or_create_for_user(user)  # ensure a referral code exists

        # Referral code redemption
        ref_code = (request.data.get('referral_code') or '').strip().upper()
        if ref_code:
            referrer_profile = UserProfile.objects.filter(
                referral_code=ref_code).select_related('user').first()
            if referrer_profile and referrer_profile.user_id != user.id:
                Referral.objects.create(
                    referrer=referrer_profile.user, referred=user, code=ref_code, credit=50)
                referrer_profile.referral_credit += 50
                referrer_profile.save(update_fields=['referral_credit'])
                my_profile = UserProfile.get_or_create_for_user(user)
                my_profile.referral_credit += 25
                my_profile.save(update_fields=['referral_credit'])
        
        # Create token
        token, created = Token.objects.get_or_create(user=user)

        log_event(request, 'signup', user, 'ok')

        return Response({
            'message': 'Account created successfully',
            'token': token.key,
            'user': {
                'id': user.id,
                'name': name,
                'phone': phone,
                'email': user.email,
                'profile_image': None,
                'bio': '',
                'location': location,
                'favorite_sports': [],
                'is_premium': False,
            }
        }, status=status.HTTP_201_CREATED)
        
    except IntegrityError:
        log_event(request, 'signup', None, 'integrity_error')
        return Response(
            {'error': 'Sign up failed. Please try logging in instead.'},
            status=status.HTTP_400_BAD_REQUEST
        )
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


# ── Leagues ──



@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([AuthRateThrottle])
def login(request):
    """
    User login endpoint
    Expected data: email, password
    """
    try:
        try:
            email = validate_email(request.data.get('email'))
            password = request.data.get('password')
            if not password:
                return Response({'error': 'Password is required'}, status=status.HTTP_400_BAD_REQUEST)
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        # Authenticate user
        user = authenticate(username=email, password=password)
        
        if user is None:
            log_event(request, 'login', None, 'failed', email)
            return Response(
                {'error': 'Invalid email or password'},
                status=status.HTTP_401_UNAUTHORIZED
            )
        
        # Get or create token
        token, created = Token.objects.get_or_create(user=user)

        log_event(request, 'login', user, 'ok')
        
        # Get full name
        full_name = f"{user.first_name} {user.last_name}".strip()
        if not full_name:
            full_name = user.username
        
        # Get profile fields
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
        
        return Response({
            'message': 'Login successful',
            'token': token.key,
            'user': {
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
        }, status=status.HTTP_200_OK)
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )




@api_view(['POST'])
def logout(request):
    """
    User logout endpoint - deletes the auth token
    """
    try:
        # Delete the user's token
        request.user.auth_token.delete()
        log_event(request, 'logout', request.user, 'ok')
        return Response(
            {'message': 'Logged out successfully'},
            status=status.HTTP_200_OK
        )
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


# Team Endpoints



@api_view(['GET', 'PATCH'])
def update_profile(request):
    """
    Get or update the current user's profile.
    PATCH expected data: name, email, profile_image, bio, location, favorite_sports (optional)
    """
    if not request.user.is_authenticated:
        return Response(
            {'error': 'Authentication required'},
            status=status.HTTP_401_UNAUTHORIZED
        )

    if request.method == 'GET':
        return Response({'user': _user_payload(request.user)})

    try:
        user = request.user
        try:
            if 'name' in request.data and request.data['name']:
                validate_string(request.data['name'], 100, 'Name')
            if 'email' in request.data and request.data['email']:
                validate_email(request.data['email'])
            if 'bio' in request.data:
                request.data['bio'] = sanitize_text(str(request.data['bio'])[:1000])
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        name = request.data.get('name')
        email = request.data.get('email')
        profile_image = request.data.get('profile_image')
        bio = request.data.get('bio')
        location = request.data.get('location')
        favorite_sports = request.data.get('favorite_sports')
        
        # Update user fields
        if name:
            name_parts = str(name).split()
            user.first_name = name_parts[0] if name_parts else ''
            user.last_name = ' '.join(name_parts[1:]) if len(name_parts) > 1 else ''
        
        if email and email != user.email:
            if User.objects.exclude(pk=user.pk).filter(email=email).exists():
                return Response(
                    {'error': 'Email already in use'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            user.email = email
        
        user.save()
        
        # Update profile fields
        if hasattr(user, 'profile'):
            if profile_image is not None:
                user.profile.profile_image = profile_image
            if bio is not None:
                user.profile.bio = bio
            if location is not None:
                user.profile.location = location
            if favorite_sports is not None:
                user.profile.favorite_sports = favorite_sports
            user.profile.save()
        
        # Get phone from profile
        return Response({
            'message': 'Profile updated successfully',
            'user': _user_payload(user),
        }, status=status.HTTP_200_OK)
        
    except Exception as e:
        return Response(
            {'error': _err_msg(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


# ── Feature 1: Leave / Cancel Match ──



@api_view(['POST'])
def upload_profile_image(request):
    if not request.user.is_authenticated:
        return Response({'error': 'Authentication required'}, status=status.HTTP_401_UNAUTHORIZED)
    uploaded = request.FILES.get('image')
    if not uploaded:
        return Response({'error': 'No image provided'}, status=status.HTTP_400_BAD_REQUEST)
    try:
        try:
            validate_image(uploaded)
        except ValueError as e:
            return Response({'error': _err_msg(e)}, status=status.HTTP_400_BAD_REQUEST)
        import uuid
        from django.core.files.storage import default_storage
        ext = uploaded.name.rsplit('.', 1)[-1] if '.' in uploaded.name else 'jpg'
        filename = f'profiles/{uuid.uuid4().hex}.{ext}'
        saved = default_storage.save(filename, uploaded)
        url = f'{settings.MEDIA_URL}{saved}'
        profile = UserProfile.get_or_create_for_user(request.user)
        profile.profile_image = url
        profile.save(update_fields=['profile_image'])
        return Response({'url': url}, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': _err_msg(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
