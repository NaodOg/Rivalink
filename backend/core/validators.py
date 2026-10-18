import re
import os
from rest_framework.throttling import AnonRateThrottle, UserRateThrottle

class AuthRateThrottle(AnonRateThrottle):
    rate = os.getenv('RATE_AUTH', '5/hour')

class CreateRateThrottle(UserRateThrottle):
    rate = os.getenv('RATE_CREATE', '10/hour')

class SensitiveWriteThrottle(UserRateThrottle):
    rate = os.getenv('RATE_SENSITIVE', '10/hour')

EMAIL_REGEX = re.compile(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
# Ethiopian mobile: +2519XXXXXXXX or 09XXXXXXXX
PHONE_REGEX = re.compile(r'^(?:\+251|0)[1-9]\d{8}$')

SPORT_CHOICES = {'soccer', 'basketball', 'tennis', 'volleyball', 'cricket', 'esports', 'other'}
TOURNAMENT_FORMATS = {'single_elimination', 'double_elimination', 'round_robin', 'group_knockout'}
MATCH_TYPES = {'pickup', 'team_vs_team'}
RESULT_TYPES = {'individual', 'team', 'draw'}
FAVORITE_TYPES = {'team', 'match', 'league'}
SKILL_LEVELS = {'any', 'beginner', 'intermediate', 'advanced'}
REPORT_CATEGORIES = {'spam', 'abuse', 'no_show', 'cheating', 'other'}

ALLOWED_IMAGE_MIME_TYPES = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'}
ALLOWED_IMAGE_EXTENSIONS = {'jpg', 'jpeg', 'png', 'webp', 'gif'}
MAX_IMAGE_SIZE_BYTES = 5 * 1024 * 1024

IMAGE_MAGIC_BYTES = [
    (b'\xff\xd8\xff', 'image/jpeg'),
    (b'\x89PNG\r\n\x1a\n', 'image/png'),
    (b'GIF87a', 'image/gif'),
    (b'GIF89a', 'image/gif'),
    (b'RIFF', 'image/webp'),
]


def validate_email(email):
    if not email or not email.strip():
        raise ValueError('Email is required')
    email = email.strip().lower()
    if len(email) > 254:
        raise ValueError('Email exceeds maximum length')
    if not EMAIL_REGEX.match(email):
        raise ValueError('Invalid email format')
    return email


def validate_phone(phone):
    if not phone or not phone.strip():
        raise ValueError('Phone number is required')
    phone = phone.strip()
    if not PHONE_REGEX.match(phone):
        raise ValueError('Invalid phone number format')
    return phone


def validate_string(value, max_length, field_name='Field'):
    if value is None:
        raise ValueError(f'{field_name} is required')
    s = str(value).strip()
    if not s:
        raise ValueError(f'{field_name} cannot be empty')
    if len(s) > max_length:
        raise ValueError(f'{field_name} exceeds maximum length of {max_length} characters')
    return s


def validate_optional_string(value, max_length, field_name='Field'):
    if not value:
        return ''
    return validate_string(value, max_length, field_name)


def validate_int(value, min_val, max_val, field_name='Field'):
    try:
        v = int(value)
    except (TypeError, ValueError):
        raise ValueError(f'{field_name} must be a valid integer')
    if v < min_val or v > max_val:
        raise ValueError(f'{field_name} must be between {min_val} and {max_val}')
    return v


def validate_optional_int(value, min_val, max_val, field_name='Field'):
    if value is None or value == '':
        return None
    return validate_int(value, min_val, max_val, field_name)


def validate_decimal(value, min_val, max_val, field_name='Field'):
    try:
        v = float(value)
    except (TypeError, ValueError):
        raise ValueError(f'{field_name} must be a valid number')
    if v < min_val or v > max_val:
        raise ValueError(f'{field_name} must be between {min_val} and {max_val}')
    return v


def validate_enum(value, allowed_set, field_name='Field'):
    if value not in allowed_set:
        raise ValueError(f'{field_name} must be one of: {", ".join(sorted(allowed_set))}')
    return value


def sanitize_text(text):
    if not text:
        return ''
    from django.utils.html import strip_tags
    return strip_tags(str(text)).strip()


def validate_password(password):
    if not password:
        raise ValueError('Password is required')
    if len(password) < 8:
        raise ValueError('Password must be at least 8 characters long')
    if len(password) > 128:
        raise ValueError('Password must not exceed 128 characters')
    if not re.search(r'[A-Z]', password):
        raise ValueError('Password must contain at least one uppercase letter')
    if not re.search(r'[a-z]', password):
        raise ValueError('Password must contain at least one lowercase letter')
    if not re.search(r'\d', password):
        raise ValueError('Password must contain at least one number')
    return password


def validate_image(uploaded_file):
    if not uploaded_file:
        raise ValueError('No file provided')
    if uploaded_file.size == 0:
        raise ValueError('Uploaded file is empty')
    if uploaded_file.size > MAX_IMAGE_SIZE_BYTES:
        raise ValueError('Image size exceeds 5MB limit')

    ext = uploaded_file.name.rsplit('.', 1)[-1].lower() if '.' in uploaded_file.name else ''
    if ext not in ALLOWED_IMAGE_EXTENSIONS:
        raise ValueError(f'File extension ".{ext}" is not allowed. Allowed: jpg, jpeg, png, webp, gif')

    content_type = (uploaded_file.content_type or '').lower()
    if content_type not in ALLOWED_IMAGE_MIME_TYPES and content_type != 'application/octet-stream':
        raise ValueError(f'File type "{content_type}" is not allowed')

    uploaded_file.seek(0)
    header = uploaded_file.read(16)
    uploaded_file.seek(0)

    valid_magic = False
    for magic, _ in IMAGE_MAGIC_BYTES:
        if header.startswith(magic):
            valid_magic = True
            break
    if not valid_magic:
        raise ValueError('File content does not match a valid image format')

    return True


def validate_date_iso(date_str, field_name='Date'):
    if not date_str:
        raise ValueError(f'{field_name} is required')
    from datetime import datetime
    try:
        return datetime.fromisoformat(date_str.replace('Z', '+00:00'))
    except (ValueError, TypeError):
        raise ValueError(f'Invalid {field_name.lower()} format. Use ISO 8601.')


def validate_boolean(value, field_name='Field'):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() in ('true', '1', 'yes')
    if isinstance(value, (int, float)):
        return bool(value)
    return False


def validate_favorite_type(value):
    return validate_enum(value, FAVORITE_TYPES, 'favorite_type')
