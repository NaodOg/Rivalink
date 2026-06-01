from django.db import models
from django.contrib.auth.models import User

class UserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    phone = models.CharField(max_length=20, blank=True)
    profile_image = models.URLField(blank=True, null=True)
    favorite_sports = models.CharField(max_length=200, blank=True, default='')
    bio = models.TextField(blank=True, default='')
    location = models.CharField(max_length=200, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.user.username}'s profile"

    @staticmethod
    def get_or_create_for_user(user):
        profile, created = UserProfile.objects.get_or_create(user=user)
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
    price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    organizer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='organized_matches')
    team = models.ForeignKey(Team, on_delete=models.SET_NULL, null=True, blank=True, related_name='matches')
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.title} - {self.sport}"


class MatchParticipant(models.Model):
    match = models.ForeignKey(Match, on_delete=models.CASCADE, related_name='participants')
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='joined_matches')
    team_group = models.CharField(max_length=10, blank=True, default='')
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('match', 'user')


class Notification(models.Model):
    TYPE_CHOICES = [
        ('match_joined', 'Player Joined Match'),
        ('match_left', 'Player Left Match'),
        ('match_cancelled', 'Match Cancelled'),
        ('chat_message', 'New Chat Message'),
        ('team_joined', 'Player Joined Team'),
        ('team_left', 'Player Left Team'),
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

    def __str__(self):
        return f"{self.title} -> {self.user.username}"


class ChatMessage(models.Model):
    match = models.ForeignKey(Match, on_delete=models.CASCADE, related_name='chat_messages')
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
    is_active = models.BooleanField(default=True)
    organizer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='organized_leagues')
    location = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} ({self.sport})"


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
        return f"Result for {self.match.title}: {self.score}"


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
    
    match = models.OneToOneField(Match, on_delete=models.CASCADE, related_name='result')
    match_type = models.CharField(max_length=20, choices=MATCH_TYPE_CHOICES, default='pickup')
    result_type = models.CharField(max_length=20, choices=RESULT_TYPE_CHOICES, default='individual')
    winner_team_id = models.IntegerField(null=True, blank=True)
    winner_user_id = models.IntegerField(null=True, blank=True)
    winning_group = models.CharField(max_length=10, blank=True, default='')
    mvp_user_id = models.IntegerField(null=True, blank=True)  # For pickup matches
    score = models.CharField(max_length=50, blank=True)
    notes = models.TextField(blank=True)
    created_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Result for {self.match.title}: {self.score}"


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
    price_per_hour = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    capacity = models.IntegerField(default=0)
    amenities = models.TextField(blank=True, default='')  # comma-separated
    images = models.TextField(blank=True, default='')  # comma-separated URLs
    opening_time = models.TimeField(null=True, blank=True)
    closing_time = models.TimeField(null=True, blank=True)
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
    
    venue = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name='bookings')
    match = models.ForeignKey(Match, on_delete=models.SET_NULL, null=True, blank=True, related_name='venue_booking')
    booked_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='venue_bookings')
    date = models.DateField()
    start_time = models.TimeField()
    end_time = models.TimeField()
    hours = models.IntegerField(default=1)
    total_price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
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


class TournamentRegistration(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ]
    
    tournament = models.ForeignKey(Tournament, on_delete=models.CASCADE, related_name='registrations')
    team = models.ForeignKey(Team, on_delete=models.CASCADE, related_name='registration_requests')
    requested_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='tournament_requests')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('tournament', 'team')

    def __str__(self):
        return f"{self.team.name} -> {self.tournament.name}"


class UserSportRating(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sport_ratings')
    sport = models.CharField(max_length=50)
    elo_rating = models.IntegerField(default=1200)
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
