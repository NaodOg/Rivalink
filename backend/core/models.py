from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone
import secrets


def _generate_referral_code():
    while True:
        code = secrets.token_hex(3).upper()
        if not UserProfile.objects.filter(referral_code=code).exists():
            return code

class UserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    phone = models.CharField(max_length=20, blank=True)
    profile_image = models.URLField(blank=True, null=True)
    favorite_sports = models.CharField(max_length=200, blank=True, default='')
    bio = models.TextField(blank=True, default='')
    location = models.CharField(max_length=200, blank=True, default='')
    is_premium = models.BooleanField(default=False)
    premium_expires = models.DateTimeField(null=True, blank=True)
    phone_verified = models.BooleanField(default=False)
    phone_code = models.CharField(max_length=6, blank=True, default='')
    phone_code_expires = models.DateTimeField(null=True, blank=True)
    reset_token = models.CharField(max_length=64, blank=True, default='')
    reset_token_expires = models.DateTimeField(null=True, blank=True)
    no_show_count = models.IntegerField(default=0)
    host_cancel_count = models.IntegerField(default=0)
    host_suspended_until = models.DateTimeField(null=True, blank=True)
    referral_code = models.CharField(max_length=12, unique=True, null=True, blank=True)
    referral_credit = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def premium_active(self):
        if not self.is_premium:
            return False
        if self.premium_expires and self.premium_expires < timezone.now():
            return False
        return True

    def __str__(self):
        return f"{self.user.username}'s profile"

    @staticmethod
    def get_or_create_for_user(user):
        profile, created = UserProfile.objects.get_or_create(user=user)
        if not profile.referral_code:
            profile.referral_code = _generate_referral_code()
            profile.save(update_fields=['referral_code'])
        return profile


class Team(models.Model):
    SPORT_CHOICES = [
        ('soccer', 'Soccer'),
        ('basketball', 'Basketball'),
        ('tennis', 'Tennis'),
        ('volleyball', 'Volleyball'),
        ('cricket', 'Cricket'),
        ('esports', 'Esports'),
        ('other', 'Other'),
    ]
    
    name = models.CharField(max_length=100)
    sport = models.CharField(max_length=50, choices=SPORT_CHOICES)
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name='owned_teams')
    description = models.TextField(blank=True)
    location = models.CharField(max_length=200, blank=True)
    max_members = models.IntegerField(default=10)
    is_active = models.BooleanField(default=True)
    is_seeking_players = models.BooleanField(default=False)
    spots_left = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.name} ({self.sport})"

    @property
    def current_members(self):
        return self.members.count()


class TeamMember(models.Model):
    ROLE_CHOICES = [
        ('owner', 'Owner'),
        ('admin', 'Admin'),
        ('member', 'Member'),
    ]
    
    team = models.ForeignKey(Team, on_delete=models.CASCADE, related_name='members')
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='team_memberships')
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default='member')
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('team', 'user')

    def __str__(self):
        return f"{self.user.username} - {self.team.name} ({self.role})"


class TeamJoinRequest(models.Model):
    team = models.ForeignKey(Team, on_delete=models.CASCADE, related_name='join_requests')
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='team_requests')
    status = models.CharField(max_length=20, default='pending')  # pending, approved, rejected
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('team', 'user')

    def __str__(self):
        return f"{self.user.username} requested to join {self.team.name}"


class Match(models.Model):
    SPORT_CHOICES = [
        ('soccer', 'Soccer'),
        ('basketball', 'Basketball'),
        ('tennis', 'Tennis'),
        ('volleyball', 'Volleyball'),
        ('cricket', 'Cricket'),
        ('esports', 'Esports'),
        ('other', 'Other'),
    ]
    
    title = models.CharField(max_length=200)
    sport = models.CharField(max_length=50, choices=SPORT_CHOICES)
    description = models.TextField(blank=True)
    location = models.CharField(max_length=200)
    date_time = models.DateTimeField()
    max_players = models.IntegerField(default=10)
    current_players = models.IntegerField(default=0)
    min_players = models.IntegerField(default=0)  # 0 = no minimum
    auto_cancel_hours = models.IntegerField(default=6)
    cancelled_reason = models.CharField(max_length=200, blank=True, default='')
    cancelled_at = models.DateTimeField(null=True, blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    skill_level = models.CharField(
        max_length=20,
        choices=[
            ('any', 'Any level'),
            ('beginner', 'Beginner'),
            ('intermediate', 'Intermediate'),
            ('advanced', 'Advanced'),
        ],
        default='any',
    )
    organizer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='organized_matches')
    team = models.ForeignKey(Team, on_delete=models.SET_NULL, null=True, blank=True, related_name='matches')
    league = models.ForeignKey('League', on_delete=models.SET_NULL, null=True, blank=True,
                               related_name='matches')
    venue = models.ForeignKey('Venue', on_delete=models.SET_NULL, null=True, blank=True,
                              related_name='hosted_matches')
    booking_status = models.CharField(
        max_length=20,
        choices=[
            ('none', 'Not requested'),
            ('requested', 'Awaiting player confirmations'),
            ('confirmed', 'Field booked'),
            ('cancelled', 'Cancelled'),
        ],
        default='none',
    )
    booking_requested_at = models.DateTimeField(null=True, blank=True)
    booking_confirmed_at = models.DateTimeField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    reminder_sent = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['date_time']),
            models.Index(fields=['is_active']),
        ]

    def __str__(self):
        return f"{self.title} - {self.sport}"


class MatchParticipant(models.Model):
    PAYMENT_STATUS_CHOICES = [
        ('unpaid', 'Unpaid'),
        ('held', 'In escrow'),
        ('released', 'Released to host'),
        ('refunded', 'Refunded'),
        ('partially_refunded', 'Partially refunded'),
        ('forfeited', 'Forfeited'),
    ]

    match = models.ForeignKey(Match, on_delete=models.CASCADE, related_name='participants')
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='joined_matches')
    team_group = models.CharField(max_length=10, blank=True, default='')
    paid = models.BooleanField(default=False)
    paid_at = models.DateTimeField(null=True, blank=True)
    amount_paid = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    payment_status = models.CharField(max_length=20, choices=PAYMENT_STATUS_CHOICES, default='unpaid')
    booking_confirmed = models.BooleanField(default=False)
    booking_confirmed_at = models.DateTimeField(null=True, blank=True)
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('match', 'user')


class MatchWaitlist(models.Model):
    match = models.ForeignKey(Match, on_delete=models.CASCADE, related_name='waitlist')
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='match_waitlists')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('match', 'user')
        ordering = ['created_at']

    def __str__(self):
        return f"{self.user.username} waiting for {self.match.title}"


class DeviceToken(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='device_tokens')
    token = models.CharField(max_length=500, unique=True)
    device_type = models.CharField(max_length=20, default='android')
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.username} ({self.device_type})"


class Notification(models.Model):
    TYPE_CHOICES = [
        ('match_joined', 'Player Joined Match'),
        ('match_left', 'Player Left Match'),
        ('match_cancelled', 'Match Cancelled'),
        ('chat_message', 'New Chat Message'),
        ('team_chat_message', 'Team Chat Message'),
        ('team_joined', 'Player Joined Team'),
        ('team_left', 'Player Left Team'),
        ('waitlist_promoted', 'Waitlist Promoted'),
        ('general', 'General'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='notifications')
    notification_type = models.CharField(max_length=30, choices=TYPE_CHOICES, default='general')
    title = models.CharField(max_length=200)
    message = models.TextField()
    related_match = models.ForeignKey(Match, on_delete=models.SET_NULL, null=True, blank=True)
    related_team = models.ForeignKey(Team, on_delete=models.SET_NULL, null=True, blank=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'is_read']),
        ]

    def __str__(self):
        return f"{self.title} -> {self.user.username}"


class ChatMessage(models.Model):
    match = models.ForeignKey(Match, on_delete=models.CASCADE, related_name='chat_messages', null=True, blank=True)
    team = models.ForeignKey(Team, on_delete=models.CASCADE, related_name='chat_messages', null=True, blank=True)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='chat_messages')
    message = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f"{self.user.username}: {self.message[:30]}..."


class League(models.Model):
    SPORT_CHOICES = [
        ('soccer', 'Soccer'),
        ('basketball', 'Basketball'),
        ('tennis', 'Tennis'),
        ('volleyball', 'Volleyball'),
        ('cricket', 'Cricket'),
        ('esports', 'Esports'),
        ('other', 'Other'),
    ]
    STATUS_CHOICES = [
        ('registration', 'Registration Open'),
        ('live', 'Live'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled'),
    ]
    
    name = models.CharField(max_length=200)
    sport = models.CharField(max_length=50, choices=SPORT_CHOICES)
    description = models.TextField(blank=True)
    format = models.CharField(max_length=50)  # e.g., "5v5", "3v3", "Doubles"
    max_teams = models.IntegerField(default=8)
    current_teams = models.IntegerField(default=0)
    entry_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    prize = models.TextField(blank=True)  # e.g., "$500 prize pool"
    start_date = models.DateTimeField()
    end_date = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='registration')
    points_win = models.IntegerField(default=3)
    points_draw = models.IntegerField(default=1)
    double_round_robin = models.BooleanField(default=False)
    champion = models.ForeignKey('Team', on_delete=models.SET_NULL, null=True, blank=True,
                                 related_name='league_titles')
    is_active = models.BooleanField(default=True)
    organizer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='organized_leagues')
    location = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['start_date']),
            models.Index(fields=['sport', 'is_active']),
        ]

    def __str__(self):
        return f"{self.name} ({self.sport})"


class LeagueFixture(models.Model):
    """A single league match between two teams (round-robin schedule)."""
    STATUS_CHOICES = [
        ('scheduled', 'Scheduled'),
        ('completed', 'Completed'),
    ]

    league = models.ForeignKey(League, on_delete=models.CASCADE, related_name='fixtures')
    round_number = models.IntegerField(default=1)
    home_team = models.ForeignKey(Team, on_delete=models.CASCADE, related_name='home_fixtures')
    away_team = models.ForeignKey(Team, on_delete=models.CASCADE, related_name='away_fixtures')
    kickoff = models.DateTimeField(null=True, blank=True)
    match = models.ForeignKey('Match', on_delete=models.SET_NULL, null=True, blank=True,
                              related_name='league_fixture')
    home_score = models.IntegerField(null=True, blank=True)
    away_score = models.IntegerField(null=True, blank=True)
    is_walkover = models.BooleanField(default=False)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='scheduled')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['round_number', 'kickoff', 'id']
        indexes = [models.Index(fields=['league', 'status'])]

    def __str__(self):
        return f"{self.home_team.name} vs {self.away_team.name} (R{self.round_number})"


class LeagueMember(models.Model):
    ROLE_CHOICES = [
        ('owner', 'Owner'),
        ('admin', 'Admin'),
        ('member', 'Member'),
    ]
    
    league = models.ForeignKey(League, on_delete=models.CASCADE, related_name='members')
    team = models.ForeignKey(Team, on_delete=models.CASCADE, related_name='league_memberships')
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default='member')
    wins = models.IntegerField(default=0)
    losses = models.IntegerField(default=0)
    draws = models.IntegerField(default=0)
    points = models.IntegerField(default=0)
    goals_for = models.IntegerField(default=0)
    goals_against = models.IntegerField(default=0)
    matches_played = models.IntegerField(default=0)
    prev_rank = models.IntegerField(default=0)  # rank before the latest result
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('league', 'team')

    def __str__(self):
        return f"{self.team.name} in {self.league.name}"

    @property
    def win_rate(self):
        total = self.wins + self.losses
        if total == 0:
            return 0
        return (self.wins / total) * 100

    @property
    def goal_difference(self):
        return self.goals_for - self.goals_against


class PlayerRating(models.Model):
    match = models.ForeignKey(Match, on_delete=models.CASCADE, related_name='ratings')
    rater = models.ForeignKey(User, on_delete=models.CASCADE, related_name='given_ratings')
    rated_user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='received_ratings')
    rating = models.IntegerField(choices=[(i, i) for i in range(1, 6)])  # 1-5 stars
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('match', 'rater', 'rated_user')

    def __str__(self):
        return f"{self.rater.username} rated {self.rated_user.username} {self.rating}/5"


class Favorite(models.Model):
    FAVORITE_TYPE_CHOICES = [
        ('team', 'Team'),
        ('match', 'Match'),
        ('league', 'League'),
    ]
    
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='favorites')
    favorite_type = models.CharField(max_length=20, choices=FAVORITE_TYPE_CHOICES)
    object_id = models.IntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'favorite_type', 'object_id')

    def __str__(self):
        return f"{self.user.username} favorited {self.favorite_type} #{self.object_id}"


class MatchResult(models.Model):
    MATCH_TYPE_CHOICES = [
        ('team_vs_team', 'Team vs Team'),
        ('pickup', 'Pickup/Social'),
    ]
    RESULT_TYPE_CHOICES = [
        ('team', 'Team Winner'),
        ('individual', 'Individual Winner'),
        ('draw', 'Draw'),
    ]
    STATUS_CHOICES = [
        ('pending', 'Pending confirmation'),
        ('confirmed', 'Confirmed'),
        ('disputed', 'Disputed'),
    ]

    match = models.OneToOneField(Match, on_delete=models.CASCADE, related_name='result')
    match_type = models.CharField(max_length=20, choices=MATCH_TYPE_CHOICES, default='pickup')
    result_type = models.CharField(max_length=20, choices=RESULT_TYPE_CHOICES, default='individual')
    winner_team = models.ForeignKey(Team, on_delete=models.SET_NULL, null=True, blank=True, related_name='winner_results')
    winner_user = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='winner_results')
    team1 = models.ForeignKey(Team, on_delete=models.SET_NULL, null=True, blank=True, related_name='result_team1')
    team2 = models.ForeignKey(Team, on_delete=models.SET_NULL, null=True, blank=True, related_name='result_team2')
    winning_group = models.CharField(max_length=10, blank=True, default='')
    mvp_user = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='mvp_results')
    score = models.CharField(max_length=50, blank=True)
    no_show_user_ids = models.CharField(max_length=500, blank=True, default='')  # comma-separated
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    rankings_applied = models.BooleanField(default=False)
    confirmed_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True)
    created_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def no_show_list(self):
        return [int(x) for x in self.no_show_user_ids.split(',') if x.strip().isdigit()]

    def __str__(self):
        return f"Result for {self.match.title}: {self.score}"


class MatchResultConfirmation(models.Model):
    """A participant's confirm/dispute vote on a match result."""
    STATUS_CHOICES = [
        ('confirmed', 'Confirmed'),
        ('disputed', 'Disputed'),
    ]

    result = models.ForeignKey(MatchResult, on_delete=models.CASCADE, related_name='confirmations')
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='result_confirmations')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='confirmed')
    note = models.CharField(max_length=300, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('result', 'user')

    def __str__(self):
        return f"{self.user.username} {self.status} {self.result_id}"


class DirectMessage(models.Model):
    sender = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sent_messages')
    recipient = models.ForeignKey(User, on_delete=models.CASCADE, related_name='received_messages')
    message = models.TextField()
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"Message from {self.sender.username} to {self.recipient.username}"


class Referee(models.Model):
    VERIFICATION_STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('verified', 'Verified'),
        ('rejected', 'Rejected'),
    ]
    
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='referee_profile')
    sports = models.CharField(max_length=500, default='')  # Comma-separated sports
    experience_years = models.IntegerField(default=0)
    certification = models.TextField(blank=True, default='')
    bio = models.TextField(blank=True, default='')
    hourly_rate = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    location = models.CharField(max_length=200, blank=True, default='')
    is_available = models.BooleanField(default=True)
    verification_status = models.CharField(max_length=20, choices=VERIFICATION_STATUS_CHOICES, default='pending')
    average_rating = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    total_matches = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Referee: {self.user.username}"

    @property
    def sport_list(self):
        return [s.strip() for s in self.sports.split(',') if s.strip()]


class RefereeBooking(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('declined', 'Declined'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled'),
    ]
    
    referee = models.ForeignKey(Referee, on_delete=models.CASCADE, related_name='bookings')
    match = models.ForeignKey(Match, on_delete=models.CASCADE, related_name='referee_bookings')
    booked_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='referee_bookings')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('referee', 'match')

    def __str__(self):
        return f"Booking: {self.referee.user.username} for {self.match.title}"


class RefereeRating(models.Model):
    booking = models.OneToOneField(RefereeBooking, on_delete=models.CASCADE, related_name='rating')
    rated_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='referee_ratings_given')
    rating = models.IntegerField(choices=[(i, i) for i in range(1, 6)])  # 1-5 stars
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Rating for {self.booking.referee.user.username}: {self.rating}"


class Venue(models.Model):
    VERIFICATION_STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('verified', 'Verified'),
        ('rejected', 'Rejected'),
    ]
    
    SPORT_CHOICES = [
        ('soccer', 'Soccer'),
        ('basketball', 'Basketball'),
        ('tennis', 'Tennis'),
        ('volleyball', 'Volleyball'),
        ('cricket', 'Cricket'),
        ('esports', 'Esports'),
        ('multiple', 'Multiple Sports'),
        ('other', 'Other'),
    ]
    
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name='owned_venues')
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True, default='')
    address = models.CharField(max_length=300)
    city = models.CharField(max_length=100)
    location = models.CharField(max_length=200, blank=True, default='')  # lat,lng
    sports = models.CharField(max_length=500, default='')  # comma-separated
    slot_price = models.DecimalField(max_digits=10, decimal_places=2, default=0)  # price per 2-hour slot
    capacity = models.IntegerField(default=0)
    amenities = models.TextField(blank=True, default='')  # comma-separated
    images = models.TextField(blank=True, default='')  # comma-separated URLs
    opening_time = models.TimeField(null=True, blank=True)
    closing_time = models.TimeField(null=True, blank=True)
    cancellation_hours = models.IntegerField(default=24)
    cancellation_fee_percent = models.IntegerField(default=0)
    is_active = models.BooleanField(default=True)
    is_available = models.BooleanField(default=True)
    verification_status = models.CharField(max_length=20, choices=VERIFICATION_STATUS_CHOICES, default='pending')
    average_rating = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    total_bookings = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = 'venues'

    def __str__(self):
        return f"{self.name} ({self.city})"

    @property
    def sport_list(self):
        return [s.strip() for s in self.sports.split(',') if s.strip()]
    
    @property
    def amenities_list(self):
        return [a.strip() for a in self.amenities.split(',') if a.strip()]
    
    @property
    def image_list(self):
        return [img.strip() for img in self.images.split(',') if img.strip()]


class VenueBooking(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('confirmed', 'Confirmed'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled'),
    ]
    PAYMENT_STATUS_CHOICES = [
        ('unpaid', 'Unpaid'),
        ('paid', 'Paid'),
        ('refunded', 'Refunded'),
    ]
    
    venue = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name='bookings')
    match = models.ForeignKey(Match, on_delete=models.SET_NULL, null=True, blank=True, related_name='venue_booking')
    booked_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='venue_bookings')
    date = models.DateField()
    start_time = models.TimeField()
    end_time = models.TimeField()
    hours = models.IntegerField(default=1)
    total_price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    payment_status = models.CharField(max_length=20, choices=PAYMENT_STATUS_CHOICES, default='unpaid')
    paid_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Booking at {self.venue.name} on {self.date}"


class VenueRating(models.Model):
    venue = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name='ratings')
    rated_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='venue_ratings_given')
    rating = models.IntegerField(choices=[(i, i) for i in range(1, 6)])  # 1-5 stars
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('venue', 'rated_by')

    def __str__(self):
        return f"Rating for {self.venue.name}: {self.rating}"


class Tournament(models.Model):
    FORMAT_CHOICES = [
        ('single_elimination', 'Single Elimination'),
        ('double_elimination', 'Double Elimination'),
        ('round_robin', 'Round Robin'),
        ('group_knockout', 'Group + Knockout'),
    ]
    
    STATUS_CHOICES = [
        ('draft', 'Draft'),
        ('registration', 'Registration Open'),
        ('live', 'Live'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled'),
    ]
    
    name = models.CharField(max_length=200)
    sport = models.CharField(max_length=50, default='soccer')
    description = models.TextField(blank=True, default='')
    format = models.CharField(max_length=30, choices=FORMAT_CHOICES, default='single_elimination')
    prize_pool = models.TextField(blank=True, default='')  # e.g., "1st: \$500, 2nd: \$250"
    entry_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    max_teams = models.IntegerField(default=8)
    current_teams = models.IntegerField(default=0)
    rounds = models.IntegerField(default=3)  # Number of rounds (log2 of max_teams for elimination)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='draft')
    start_date = models.DateTimeField()
    end_date = models.DateTimeField(null=True, blank=True)
    organizer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='organized_tournaments')
    venue = models.ForeignKey(Venue, on_delete=models.SET_NULL, null=True, blank=True, related_name='tournaments')
    location = models.CharField(max_length=200, blank=True, default='')
    rules = models.TextField(blank=True, default='')
    is_public = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['status']),
            models.Index(fields=['start_date']),
        ]

    def __str__(self):
        return f"{self.name} ({self.get_format_display()})"


class TournamentTeam(models.Model):
    STATUS_CHOICES = [
        ('registered', 'Registered'),
        ('checked_in', 'Checked In'),
        ('active', 'Active'),
        ('eliminated', 'Eliminated'),
        ('winner', 'Winner'),
        ('runner_up', 'Runner Up'),
    ]
    
    tournament = models.ForeignKey(Tournament, on_delete=models.CASCADE, related_name='teams')
    team = models.ForeignKey(Team, on_delete=models.CASCADE, related_name='tournaments')
    seed = models.IntegerField(default=0)  # Bracket seed position
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='registered')
    registered_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='tournament_registrations')
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('tournament', 'team')

    def __str__(self):
        return f"{self.team.name} in {self.tournament.name}"


class TournamentMatch(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('scheduled', 'Scheduled'),
        ('live', 'Live'),
        ('completed', 'Completed'),
    ]
    
    tournament = models.ForeignKey(Tournament, on_delete=models.CASCADE, related_name='matches')
    round_number = models.IntegerField(default=1)  # 1 = quarterfinals, 2 = semifinals, etc.
    match_number = models.IntegerField(default=1)  # Match position within round
    team1 = models.ForeignKey(TournamentTeam, on_delete=models.SET_NULL, null=True, blank=True, related_name='match_as_team1')
    team2 = models.ForeignKey(TournamentTeam, on_delete=models.SET_NULL, null=True, blank=True, related_name='match_as_team2')
    winner = models.ForeignKey(TournamentTeam, on_delete=models.SET_NULL, null=True, blank=True, related_name='match_as_winner')
    score1 = models.IntegerField(default=-1)  # -1 means not played
    score2 = models.IntegerField(default=-1)
    scheduled_time = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    bracket_position = models.CharField(max_length=20, default='')  # e.g., "A1", "B2" for bracket display
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Round {self.round_number} Match {self.match_number}"

    @property
    def is_bye(self):
        return (self.team1 is None) or (self.team2 is None)

    @property
    def team1_name(self):
        return self.team1.team.name if self.team1 else 'TBD'

    @property
    def team2_name(self):
        return self.team2.team.name if self.team2 else 'TBD'


class UserSportRating(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sport_ratings')
    sport = models.CharField(max_length=50)
    elo_rating = models.IntegerField(default=1200)
    rating_deviation = models.FloatField(default=350.0)
    volatility = models.FloatField(default=0.06)
    last_rated_at = models.DateTimeField(null=True, blank=True)
    matches_played = models.IntegerField(default=0)
    wins = models.IntegerField(default=0)
    losses = models.IntegerField(default=0)
    draws = models.IntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('user', 'sport')
        verbose_name = 'User Sport Rating'

    def __str__(self):
        return f"{self.user.username} ({self.sport}): {self.elo_rating}"


class TeamRanking(models.Model):
    team = models.ForeignKey(Team, on_delete=models.CASCADE, related_name='rankings')
    sport = models.CharField(max_length=50)
    wins = models.IntegerField(default=0)
    losses = models.IntegerField(default=0)
    draws = models.IntegerField(default=0)
    points = models.IntegerField(default=0)
    goals_for = models.IntegerField(default=0)
    goals_against = models.IntegerField(default=0)
    matches_played = models.IntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('team', 'sport')
        verbose_name = 'Team Ranking'

    @property
    def goal_difference(self):
        return self.goals_for - self.goals_against

    @property
    def win_rate(self):
        total = self.wins + self.losses + self.draws
        if total == 0:
            return 0
        return round((self.wins / total) * 100, 1)

    def __str__(self):
        return f"{self.team.name} ({self.sport}): {self.points} pts"


class Payment(models.Model):
    PAYMENT_TYPES = [
        ('premium', 'Premium Subscription'),
        ('venue_booking', 'Venue Booking'),
        ('match_share', 'Match Share (escrow)'),
    ]
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('success', 'Success'),
        ('failed', 'Failed'),
        ('refunded', 'Refunded'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='payments')
    tx_ref = models.CharField(max_length=100, unique=True)
    chapa_tx_id = models.CharField(max_length=100, blank=True, default='')
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=10, default='ETB')
    payment_type = models.CharField(max_length=20, choices=PAYMENT_TYPES)
    reference_type = models.CharField(max_length=32, blank=True, default='')
    reference_id = models.IntegerField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    description = models.CharField(max_length=500, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.user.username} - {self.payment_type} - {self.status} ({self.tx_ref})"


class PlatformTransaction(models.Model):
    """Platform revenue ledger — one row per fee/commission the app earns."""

    KIND_CHOICES = [
        ('venue_commission', 'Venue Booking Commission'),
        ('host_fee', 'Match Host Fee'),
        ('referee_commission', 'Referee Booking Commission'),
        ('tournament_fee', 'Tournament Entry Fee'),
        ('league_fee', 'League Entry Fee'),
        ('premium', 'Premium Subscription'),
        ('featured_listing', 'Featured Listing'),
        ('match_share', 'Match Share Escrow'),
        ('cancellation_fee', 'Cancellation Fee'),
        ('host_penalty', 'Host Penalty (owed)'),
    ]
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('collected', 'Collected'),
        ('refunded', 'Refunded'),
        ('waived', 'Waived'),
    ]

    kind = models.CharField(max_length=32, choices=KIND_CHOICES)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=10, default='ETB')
    payer = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True,
                              related_name='platform_transactions')
    reference_type = models.CharField(max_length=32, blank=True, default='')
    reference_id = models.IntegerField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    note = models.CharField(max_length=300, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['kind']),
            models.Index(fields=['created_at']),
        ]

    def __str__(self):
        return f"{self.get_kind_display()}: {self.amount} {self.currency} ({self.status})"


class AnalyticsEvent(models.Model):
    """One product-analytics event (client batch or server-side action)."""

    user = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True,
                             related_name='analytics_events')
    anon_id = models.CharField(max_length=64, blank=True, default='', db_index=True)
    session_id = models.CharField(max_length=64, blank=True, default='')
    name = models.CharField(max_length=80)
    properties = models.JSONField(default=dict, blank=True)
    platform = models.CharField(max_length=20, default='android')
    app_version = models.CharField(max_length=20, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['name', 'created_at']),
            models.Index(fields=['user', 'created_at']),
            models.Index(fields=['created_at']),
        ]

    def __str__(self):
        return f"{self.name} — {self.created_at:%Y-%m-%d %H:%M}"


class AuditLog(models.Model):
    """Security audit trail — auth events and sensitive actions."""

    user = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True,
                             related_name='audit_logs')
    action = models.CharField(max_length=64)
    status = models.CharField(max_length=16, default='ok')
    ip = models.CharField(max_length=64, blank=True, default='')
    user_agent = models.CharField(max_length=255, blank=True, default='')
    detail = models.CharField(max_length=500, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['action']),
            models.Index(fields=['created_at']),
        ]

    def __str__(self):
        return f"{self.action} ({self.status})"


class Report(models.Model):
    CATEGORY_CHOICES = [
        ('spam', 'Spam'),
        ('abuse', 'Abuse'),
        ('no_show', 'No-show'),
        ('cheating', 'Cheating'),
        ('other', 'Other'),
    ]
    STATUS_CHOICES = [
        ('open', 'Open'),
        ('reviewed', 'Reviewed'),
        ('dismissed', 'Dismissed'),
    ]

    reporter = models.ForeignKey(User, on_delete=models.CASCADE, related_name='reports_made')
    target_user = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='reports_received', null=True, blank=True)
    match = models.ForeignKey(Match, on_delete=models.SET_NULL, null=True, blank=True)
    category = models.CharField(max_length=30, choices=CATEGORY_CHOICES, default='other')
    details = models.TextField(blank=True, default='')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='open')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.reporter.username} -> {self.category} ({self.status})"


class Block(models.Model):
    blocker = models.ForeignKey(User, on_delete=models.CASCADE, related_name='blocks_made')
    blocked = models.ForeignKey(User, on_delete=models.CASCADE, related_name='blocks_received')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('blocker', 'blocked')

    def __str__(self):
        return f"{self.blocker.username} blocked {self.blocked.username}"


class Follow(models.Model):
    follower = models.ForeignKey(User, on_delete=models.CASCADE, related_name='following_set')
    following = models.ForeignKey(User, on_delete=models.CASCADE, related_name='followers_set')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('follower', 'following')

    def __str__(self):
        return f"{self.follower.username} → {self.following.username}"


class Referral(models.Model):
    referrer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='referrals_made')
    referred = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True, related_name='referral_source')
    code = models.CharField(max_length=12)
    credit = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.referrer.username} referred {self.referred.username if self.referred else '—'}"


class RecommendationExposure(models.Model):
    """A ranked match that was actually shown to a user (for learning labels)."""

    user = models.ForeignKey(User, on_delete=models.CASCADE,
                             related_name='recommendation_exposures')
    match = models.ForeignKey(Match, on_delete=models.CASCADE,
                              related_name='recommendation_exposures')
    surface = models.CharField(max_length=30, default='recommendations')
    variant = models.CharField(max_length=20, blank=True, default='')
    score = models.FloatField(default=0)
    features = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'created_at']),
            models.Index(fields=['match', 'created_at']),
        ]

    def __str__(self):
        return f'{self.user.username} saw {self.match_id} ({self.surface})'


class ModelArtifact(models.Model):
    """Trained model weights + metadata (pure-Python models, no ML service)."""

    name = models.CharField(max_length=50, unique=True)
    weights = models.JSONField(default=dict, blank=True)
    meta = models.JSONField(default=dict, blank=True)
    samples = models.IntegerField(default=0)
    trained_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'{self.name} ({self.samples} samples)'


class NotificationBandit(models.Model):
    """Beta(alpha, beta) posterior for one notification arm."""

    user = models.ForeignKey(User, on_delete=models.CASCADE,
                             related_name='notification_bandits')
    experiment = models.CharField(max_length=50, default='send_time')
    arm = models.CharField(max_length=30)
    alpha = models.IntegerField(default=1)
    beta = models.IntegerField(default=1)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('user', 'experiment', 'arm')
        ordering = ['-updated_at']

    def __str__(self):
        return f'{self.user.username} {self.experiment}:{self.arm} ({self.alpha}/{self.beta})'

