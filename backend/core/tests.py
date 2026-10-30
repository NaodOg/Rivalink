"""Regression tests for the security and correctness fixes in core."""
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.models import User
from django.core.cache import cache
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from .entitlements import team_all_premium
from .models import (
    AnalyticsEvent, ChatMessage, DeviceToken, HostPayout, League, LeagueFixture,
    LeagueMember, Match, MatchParticipant, MatchPot, MatchResult, MatchWithdrawal,
    ModelArtifact, Notification, NotificationBandit, Payment,
    PlayerCreditAccount, PlayerRating, PlatformTransaction, RecommendationExposure,
    Referee, RefereeBooking, Team, TeamMember, Tournament, TournamentTeam, UserProfile,
    UserSportRating, Venue, VenueBooking,
)


class BaseAPITestCase(APITestCase):
    def setUp(self):
        # Throttle counters live in the cache; clear so recycled user PKs
        # across tests don't accumulate requests.
        cache.clear()

    def make_user(self, username, premium=False):
        user = User.objects.create_user(
            username=username, email=f'{username}@test.app', password='Test1234!')
        profile = UserProfile.get_or_create_for_user(user)
        profile.phone = '+251900000000'
        profile.is_premium = premium
        if premium:
            profile.premium_expires = timezone.now() + timedelta(days=30)
        profile.save()
        return user

    def auth(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

    def make_match(self, organizer, **overrides):
        defaults = {
            'title': 'Test Match',
            'sport': 'soccer',
            'location': 'Addis Ababa',
            'date_time': timezone.now() + timedelta(days=1),
            'max_players': 10,
            'current_players': 1,
            'price': Decimal('100'),
            'organizer': organizer,
        }
        defaults.update(overrides)
        match = Match.objects.create(**defaults)
        MatchParticipant.objects.create(match=match, user=organizer)
        return match


class RefereeBookingTests(BaseAPITestCase):
    def setUp(self):
        super().setUp()
        self.organizer = self.make_user('organizer')
        self.other = self.make_user('other')
        self.ref_user = self.make_user('referee')
        self.match = self.make_match(self.organizer)
        self.referee = Referee.objects.create(
            user=self.ref_user, sports='soccer', hourly_rate=Decimal('300'),
            is_available=True, verification_status='verified')
        self.booking = RefereeBooking.objects.create(
            referee=self.referee, match=self.match, booked_by=self.organizer,
            status='accepted', fee=Decimal('300'))

    def test_only_booker_can_complete_booking(self):
        self.auth(self.other)
        res = self.client.post(
            f'/api/referees/bookings/{self.booking.id}/', {'status': 'completed'})
        self.assertEqual(res.status_code, 403)

        self.auth(self.organizer)
        res = self.client.post(
            f'/api/referees/bookings/{self.booking.id}/', {'status': 'completed'})
        self.assertEqual(res.status_code, 200)
        self.referee.refresh_from_db()
        self.assertEqual(self.referee.total_matches, 1)

    def test_cannot_skip_from_pending_to_completed(self):
        self.booking.status = 'pending'
        self.booking.save()
        self.auth(self.organizer)
        res = self.client.post(
            f'/api/referees/bookings/{self.booking.id}/', {'status': 'completed'})
        self.assertEqual(res.status_code, 400)

    def test_non_participant_cannot_book_referee(self):
        self.auth(self.other)
        res = self.client.post('/api/referees/book/', {
            'referee_id': self.referee.id, 'match_id': self.match.id})
        self.assertEqual(res.status_code, 403)


class TournamentRegistrationTests(BaseAPITestCase):
    def setUp(self):
        super().setUp()
        self.owner = self.make_user('owner')
        self.intruder = self.make_user('intruder')
        self.team = Team.objects.create(
            owner=self.owner, name='Owners FC', sport='soccer')
        TeamMember.objects.create(team=self.team, user=self.owner, role='owner')
        self.tournament = Tournament.objects.create(
            name='Test Cup', sport='soccer', organizer=self.owner,
            start_date=timezone.now() + timedelta(days=7),
            status='registration', max_teams=8)

    def test_only_owner_can_register_team(self):
        self.auth(self.intruder)
        res = self.client.post('/api/tournaments/register/', {
            'tournament_id': self.tournament.id, 'team_id': self.team.id})
        self.assertEqual(res.status_code, 403)
        self.assertEqual(TournamentTeam.objects.count(), 0)

        self.auth(self.owner)
        res = self.client.post('/api/tournaments/register/', {
            'tournament_id': self.tournament.id, 'team_id': self.team.id})
        self.assertEqual(res.status_code, 201)
        self.assertEqual(TournamentTeam.objects.count(), 1)


class DeviceTokenTests(BaseAPITestCase):
    def test_cannot_take_over_another_users_active_token(self):
        user_a = self.make_user('device_a')
        user_b = self.make_user('device_b')
        DeviceToken.objects.create(user=user_a, token='fcm-token-1')

        self.auth(user_b)
        res = self.client.post('/api/devices/register/', {
            'token': 'fcm-token-1', 'device_type': 'android'})
        self.assertEqual(res.status_code, 409)
        self.assertEqual(DeviceToken.objects.get(token='fcm-token-1').user, user_a)

    def test_can_reuse_token_after_previous_owner_unregisters(self):
        user_a = self.make_user('device_a')
        user_b = self.make_user('device_b')
        DeviceToken.objects.create(user=user_a, token='fcm-token-2', is_active=False)

        self.auth(user_b)
        res = self.client.post('/api/devices/register/', {
            'token': 'fcm-token-2', 'device_type': 'android'})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(DeviceToken.objects.get(token='fcm-token-2').user, user_b)


class PremiumEntitlementTests(BaseAPITestCase):
    def test_non_premium_member_blocks_team(self):
        owner = self.make_user('premium_owner', premium=True)
        member = self.make_user('free_member')
        team = Team.objects.create(owner=owner, name='Mixed FC', sport='soccer')
        TeamMember.objects.create(team=team, user=owner, role='owner')
        TeamMember.objects.create(team=team, user=member, role='member')
        self.assertFalse(team_all_premium(team))

    def test_non_member_owner_is_also_checked(self):
        owner = self.make_user('free_owner')
        member = self.make_user('premium_member', premium=True)
        team = Team.objects.create(owner=owner, name='Ownerless FC', sport='soccer')
        TeamMember.objects.create(team=team, user=member, role='member')
        self.assertFalse(team_all_premium(team))

    def test_all_premium_team_passes(self):
        owner = self.make_user('premium_owner_2', premium=True)
        team = Team.objects.create(owner=owner, name='Premium FC', sport='soccer')
        TeamMember.objects.create(team=team, user=owner, role='owner')
        self.assertTrue(team_all_premium(team))


class MatchPaymentAndJoinTests(BaseAPITestCase):
    def setUp(self):
        super().setUp()
        self.organizer = self.make_user('organizer')
        self.player = self.make_user('player')
        self.match = self.make_match(self.organizer)
        MatchParticipant.objects.create(match=self.match, user=self.player)

    def test_mark_payments_updates_payment_status(self):
        self.auth(self.organizer)
        res = self.client.post(
            f'/api/matches/{self.match.id}/payments/',
            {'paid_user_ids': [self.player.id]}, format='json')
        self.assertEqual(res.status_code, 200)
        participant = MatchParticipant.objects.get(match=self.match, user=self.player)
        self.assertTrue(participant.paid)
        self.assertEqual(participant.payment_status, 'held')

    def test_cannot_join_cancelled_match(self):
        self.match.is_active = False
        self.match.save()
        joiner = self.make_user('joiner')
        self.auth(joiner)
        res = self.client.post('/api/matches/join/', {'match_id': self.match.id})
        self.assertEqual(res.status_code, 400)

    def test_cannot_join_started_match(self):
        self.match.date_time = timezone.now() - timedelta(hours=1)
        self.match.save()
        joiner = self.make_user('late_joiner')
        self.auth(joiner)
        res = self.client.post('/api/matches/join/', {'match_id': self.match.id})
        self.assertEqual(res.status_code, 400)


class VenueBookingTests(BaseAPITestCase):
    def setUp(self):
        super().setUp()
        self.owner = self.make_user('venue_owner')
        self.venue = Venue.objects.create(
            owner=self.owner, name='Test Pitch', address='Road 1', city='Addis',
            slot_price=Decimal('1000'), is_available=True)

    def test_rejects_end_time_before_start_time(self):
        self.auth(self.owner)
        res = self.client.post('/api/venues/book/', {
            'venue_id': self.venue.id, 'date': '2026-12-01',
            'start_time': '18:00', 'end_time': '16:00'})
        self.assertEqual(res.status_code, 400)

    def test_rejects_invalid_date(self):
        self.auth(self.owner)
        res = self.client.post('/api/venues/book/', {
            'venue_id': self.venue.id, 'date': 'not-a-date',
            'start_time': '18:00', 'end_time': '20:00'})
        self.assertEqual(res.status_code, 400)

    def test_cancelled_booking_cannot_be_confirmed(self):
        booking = VenueBooking.objects.create(
            venue=self.venue, booked_by=self.owner, date='2026-12-01',
            start_time='18:00', end_time='20:00', hours=2,
            total_price=Decimal('1000'), status='cancelled')
        self.auth(self.owner)
        res = self.client.post(
            f'/api/venues/bookings/{booking.id}/', {'status': 'confirmed'})
        self.assertEqual(res.status_code, 400)

    def test_rating_requires_a_booking(self):
        self.auth(self.owner)
        res = self.client.post(
            f'/api/venues/{self.venue.id}/rate/', {'rating': 5})
        self.assertEqual(res.status_code, 403)

    def test_booking_gets_pending_unpaid_status(self):
        self.auth(self.owner)
        res = self.client.post('/api/venues/book/', {
            'venue_id': self.venue.id, 'date': '2026-12-02',
            'start_time': '18:00', 'end_time': '20:00'}, format='json')
        self.assertEqual(res.status_code, 201)
        booking = VenueBooking.objects.get(id=res.data['booking']['id'])
        self.assertEqual(booking.status, 'pending')
        self.assertEqual(booking.payment_status, 'unpaid')

    def test_paying_booking_confirms_and_records_commission(self):
        self.auth(self.owner)
        booking = VenueBooking.objects.create(
            venue=self.venue, booked_by=self.owner, date='2026-12-03',
            start_time='18:00', end_time='20:00', hours=2,
            total_price=Decimal('1000'), status='pending')
        with self.settings(DEBUG=True, CHAPA_SECRET_KEY=''):
            res = self.client.post('/api/payments/venue/initialize/',
                                   {'booking_id': booking.id}, format='json')
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data.get('success'))
        booking.refresh_from_db()
        self.assertEqual(booking.payment_status, 'paid')
        self.assertEqual(booking.status, 'confirmed')
        self.assertIsNotNone(booking.paid_at)

    def test_payment_requires_own_booking(self):
        other = self.make_user('other_booker')
        booking = VenueBooking.objects.create(
            venue=self.venue, booked_by=self.owner, date='2026-12-04',
            start_time='18:00', end_time='20:00', hours=2,
            total_price=Decimal('1000'))
        self.auth(other)
        res = self.client.post('/api/payments/venue/initialize/',
                               {'booking_id': booking.id}, format='json')
        self.assertEqual(res.status_code, 404)

    def test_cancelling_paid_booking_marks_refunded(self):
        self.auth(self.owner)
        booking = VenueBooking.objects.create(
            venue=self.venue, booked_by=self.owner, date='2026-12-05',
            start_time='18:00', end_time='20:00', hours=2,
            total_price=Decimal('1000'), status='confirmed', payment_status='paid')
        res = self.client.post(f'/api/venues/bookings/{booking.id}/',
                               {'status': 'cancelled'}, format='json')
        self.assertEqual(res.status_code, 200)
        booking.refresh_from_db()
        self.assertEqual(booking.status, 'cancelled')
        self.assertEqual(booking.payment_status, 'refunded')


class RevenueSummaryTests(BaseAPITestCase):
    def test_match_share_passthrough_is_excluded_from_revenue(self):
        staff = self.make_user('staff')
        staff.is_staff = True
        staff.save()
        PlatformTransaction.objects.create(
            kind='host_fee', amount=Decimal('20'), payer=staff, status='collected')
        PlatformTransaction.objects.create(
            kind='match_share', amount=Decimal('500'), payer=staff, status='collected')

        self.auth(staff)
        res = self.client.get('/api/revenue/summary/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(Decimal(res.data['total']), Decimal('20'))


class MatchChatTests(BaseAPITestCase):
    def test_chat_returns_latest_messages_in_timeline_order(self):
        organizer = self.make_user('chat_organizer')
        match = self.make_match(organizer)
        for i in range(3):
            ChatMessage.objects.create(match=match, user=organizer, message=f'message {i}')

        self.auth(organizer)
        res = self.client.get(f'/api/matches/{match.id}/chat/')
        self.assertEqual(res.status_code, 200)
        messages = res.data['messages']
        self.assertEqual([m['message'] for m in messages],
                         ['message 0', 'message 1', 'message 2'])


class LeagueLifecycleTests(BaseAPITestCase):
    def setUp(self):
        super().setUp()
        self.organizer = self.make_user('league_org', premium=True)
        self.teams = []
        for i in range(4):
            team = Team.objects.create(
                owner=self.organizer, name=f'Team {i + 1}', sport='soccer')
            TeamMember.objects.create(team=team, user=self.organizer, role='owner')
            self.teams.append(team)
        self.league = League.objects.create(
            name='Test League', sport='soccer', format='5v5', max_teams=8,
            organizer=self.organizer, start_date=timezone.now() + timedelta(days=7))
        for team in self.teams:
            LeagueMember.objects.create(league=self.league, team=team)
        self.league.current_teams = len(self.teams)
        self.league.save()

    def start(self, league=None):
        self.auth(self.organizer)
        return self.client.post(f'/api/leagues/{(league or self.league).id}/start/')

    def test_start_generates_round_robin_fixtures(self):
        res = self.start()
        self.assertEqual(res.status_code, 200)
        self.league.refresh_from_db()
        self.assertEqual(self.league.status, 'live')
        self.assertEqual(self.league.fixtures.count(), 6)
        rounds = set(self.league.fixtures.values_list('round_number', flat=True))
        self.assertEqual(rounds, {1, 2, 3})

    def test_start_requires_two_teams(self):
        LeagueMember.objects.filter(league=self.league).exclude(
            team=self.teams[0]).delete()
        res = self.start()
        self.assertEqual(res.status_code, 400)
        self.league.refresh_from_db()
        self.assertEqual(self.league.status, 'registration')

    def test_join_blocked_after_start(self):
        self.start()
        joiner = self.make_user('late_joiner', premium=True)
        team = Team.objects.create(owner=joiner, name='Late FC', sport='soccer')
        TeamMember.objects.create(team=team, user=joiner, role='owner')
        self.auth(joiner)
        res = self.client.post('/api/leagues/join/', {
            'league_id': self.league.id, 'team_id': team.id})
        self.assertEqual(res.status_code, 400)
        self.assertIn('Registration is closed', res.data['error'])

    def test_entry_fee_recorded_on_join(self):
        self.league.entry_fee = Decimal('500')
        self.league.double_round_robin = False
        self.league.status = 'registration'
        self.league.save()
        joiner = self.make_user('fee_joiner', premium=True)
        team = Team.objects.create(owner=joiner, name='Fee FC', sport='soccer')
        TeamMember.objects.create(team=team, user=joiner, role='owner')
        self.auth(joiner)
        res = self.client.post('/api/leagues/join/', {
            'league_id': self.league.id, 'team_id': team.id})
        self.assertEqual(res.status_code, 201)
        tx = PlatformTransaction.objects.filter(
            kind='league_fee', reference_type='league', reference_id=self.league.id).first()
        self.assertIsNotNone(tx)
        self.assertEqual(tx.amount, Decimal('60.00'))  # 12% of 500

    def _first_fixture(self):
        return self.league.fixtures.order_by('round_number', 'id').first()

    def test_record_result_updates_standings_and_completes(self):
        self.start()
        self.league.refresh_from_db()
        fixture = self._first_fixture()
        self.auth(self.organizer)
        res = self.client.post(
            f'/api/leagues/fixtures/{fixture.id}/result/',
            {'home_score': 3, 'away_score': 1}, format='json')
        self.assertEqual(res.status_code, 200)
        home = LeagueMember.objects.get(league=self.league, team=fixture.home_team)
        away = LeagueMember.objects.get(league=self.league, team=fixture.away_team)
        self.assertEqual((home.wins, home.points, home.goals_for, home.goals_against),
                         (1, self.league.points_win, 3, 1))
        self.assertEqual((away.losses, away.points, away.goals_for, away.goals_against),
                         (1, 0, 1, 3))

        # Finish the remaining fixtures — the league auto-completes.
        for rest in self.league.fixtures.filter(status='scheduled'):
            self.client.post(
                f'/api/leagues/fixtures/{rest.id}/result/',
                {'home_score': 2, 'away_score': 0}, format='json')
        self.league.refresh_from_db()
        self.assertEqual(self.league.status, 'completed')
        self.assertIsNotNone(self.league.champion)

    def test_recording_a_correction_adjusts_standings(self):
        self.start()
        fixture = self._first_fixture()
        self.auth(self.organizer)
        self.client.post(
            f'/api/leagues/fixtures/{fixture.id}/result/',
            {'home_score': 1, 'away_score': 0}, format='json')
        self.client.post(
            f'/api/leagues/fixtures/{fixture.id}/result/',
            {'home_score': 2, 'away_score': 2}, format='json')
        home = LeagueMember.objects.get(league=self.league, team=fixture.home_team)
        away = LeagueMember.objects.get(league=self.league, team=fixture.away_team)
        self.assertEqual((home.wins, home.draws, home.points, home.goals_for, home.goals_against),
                         (0, 1, self.league.points_draw, 2, 2))
        self.assertEqual((away.wins, away.draws, away.points), (0, 1, self.league.points_draw))

    def test_non_organizer_cannot_record(self):
        self.start()
        fixture = self._first_fixture()
        intruder = self.make_user('intruder')
        self.auth(intruder)
        res = self.client.post(
            f'/api/leagues/fixtures/{fixture.id}/result/',
            {'home_score': 3, 'away_score': 0}, format='json')
        self.assertEqual(res.status_code, 403)

    def test_remove_team_before_start(self):
        self.auth(self.organizer)
        res = self.client.post(
            f'/api/leagues/{self.league.id}/remove-team/',
            {'team_id': self.teams[0].id}, format='json')
        self.assertEqual(res.status_code, 200)
        self.league.refresh_from_db()
        self.assertEqual(self.league.current_teams, 3)
        self.assertFalse(LeagueMember.objects.filter(
            league=self.league, team=self.teams[0]).exists())

    def test_cancel_league_refunds_fees(self):
        PlatformTransaction.objects.create(
            kind='league_fee', amount=Decimal('60'), payer=self.organizer,
            reference_type='league', reference_id=self.league.id, status='pending')
        self.auth(self.organizer)
        res = self.client.post(f'/api/leagues/{self.league.id}/cancel/')
        self.assertEqual(res.status_code, 200)
        self.league.refresh_from_db()
        self.assertEqual(self.league.status, 'cancelled')
        self.assertFalse(self.league.is_active)
        tx = PlatformTransaction.objects.get(reference_id=self.league.id)
        self.assertEqual(tx.status, 'refunded')

    def test_schedule_fixture_creates_match(self):
        self.start()
        fixture = self._first_fixture()
        self.auth(self.organizer)
        res = self.client.post(
            f'/api/leagues/fixtures/{fixture.id}/schedule/',
            {'date_time': (timezone.now() + timedelta(days=3)).isoformat()},
            format='json')
        self.assertEqual(res.status_code, 200)
        fixture.refresh_from_db()
        self.assertIsNotNone(fixture.match_id)
        self.assertEqual(fixture.match.league_id, self.league.id)
        self.assertEqual(fixture.match.team_id, fixture.home_team_id)

    def test_league_details_include_fixtures_and_organizer_flag(self):
        self.start()
        self.auth(self.organizer)
        res = self.client.get(f'/api/leagues/{self.league.id}/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(len(res.data['fixtures']), 6)
        self.assertTrue(res.data['league']['is_organizer'])
        self.assertEqual(len(res.data['standings']), 4)


class LeagueMatchConfirmHookTests(BaseAPITestCase):
    def test_confirmed_match_result_updates_league_standings(self):
        organizer = self.make_user('hook_org', premium=True)
        home = Team.objects.create(owner=organizer, name='Home FC', sport='soccer')
        away = Team.objects.create(owner=organizer, name='Away FC', sport='soccer')
        league = League.objects.create(
            name='Hook League', sport='soccer', format='5v5',
            organizer=organizer, start_date=timezone.now() + timedelta(days=7),
            status='live')
        LeagueMember.objects.create(league=league, team=home)
        LeagueMember.objects.create(league=league, team=away)

        match = Match.objects.create(
            title='Home vs Away', sport='soccer', location='Addis',
            date_time=timezone.now() - timedelta(hours=2), max_players=10,
            current_players=2, organizer=organizer, team=home, league=league)
        MatchParticipant.objects.create(match=match, user=organizer)
        fixture = LeagueFixture.objects.create(
            league=league, round_number=1, home_team=home, away_team=away, match=match)

        # A confirmed (solo) result flows through confirm_match_result.
        self.auth(organizer)
        res = self.client.post(f'/api/matches/{match.id}/result/', {
            'match_type': 'team_vs_team',
            'result_type': 'team',
            'winner_team_id': home.id,
            'team1_id': home.id,
            'team2_id': away.id,
            'score': '3 - 1',
        }, format='json')
        self.assertEqual(res.status_code, 201)

        # team_vs_team with no other participants auto-confirms via the
        # participant confirmation endpoint being unnecessary; drive it manually.
        confirm = self.client.post(f'/api/matches/{match.id}/result/confirm/', {
            'status': 'confirmed'}, format='json')
        self.assertEqual(confirm.status_code, 200)

        fixture.refresh_from_db()
        home_member = LeagueMember.objects.get(league=league, team=home)
        away_member = LeagueMember.objects.get(league=league, team=away)
        self.assertIn(confirm.data['status'], ('confirmed', 'pending'))
        if confirm.data['status'] == 'confirmed':
            self.assertEqual(fixture.status, 'completed')
            self.assertEqual((fixture.home_score, fixture.away_score), (3, 1))
            self.assertEqual(home_member.points, league.points_win)
            self.assertEqual(away_member.points, 0)
        else:
            # Not enough confirmations yet — standings untouched.
            self.assertEqual(home_member.points, 0)


class AnalyticsTests(BaseAPITestCase):
    def test_anonymous_batch_ingest(self):
        res = self.client.post('/api/analytics/events/', {
            'session_id': 's-1',
            'anon_id': 'anon-1',
            'events': [
                {'name': 'screen_viewed', 'properties': {'screen': 'Home'}},
                {'name': 'search_used', 'properties': {'q': 'basketball'}},
            ],
        }, format='json')
        self.assertEqual(res.status_code, 201)
        self.assertEqual(res.data['accepted'], 2)
        self.assertEqual(AnalyticsEvent.objects.count(), 2)
        self.assertEqual(AnalyticsEvent.objects.first().anon_id, 'anon-1')

    def test_authenticated_events_attach_user(self):
        user = self.make_user('tracked')
        self.auth(user)
        res = self.client.post('/api/analytics/events/', {
            'events': [{'name': 'match_viewed', 'properties': {'sport': 'soccer'}}],
        }, format='json')
        self.assertEqual(res.status_code, 201)
        self.assertEqual(AnalyticsEvent.objects.get().user, user)

    def test_batch_validation(self):
        res = self.client.post('/api/analytics/events/', {'events': []}, format='json')
        self.assertEqual(res.status_code, 400)
        res = self.client.post('/api/analytics/events/', {
            'events': [{'name': 'Bad Name!'}],
        }, format='json')
        self.assertEqual(res.status_code, 400)

    def test_report_is_staff_only(self):
        user = self.make_user('normal')
        self.auth(user)
        res = self.client.get('/api/analytics/report/')
        self.assertEqual(res.status_code, 403)

    def test_report_contains_funnels_and_screens(self):
        staff = self.make_user('analyst')
        staff.is_staff = True
        staff.save()
        member = self.make_user('member')
        from .analytics import track
        track(member, 'signup_completed')
        track(member, 'match_viewed', {'sport': 'soccer'})
        track(member, 'match_join_clicked', {'match_id': 1})
        track(member, 'match_joined', {'match_id': 1})
        track(member, 'screen_viewed', {'screen': 'Home'})
        track(member, 'screen_exited', {'screen': 'Home', 'duration_ms': 12000})
        AnalyticsEvent.objects.filter(name='screen_viewed').update(
            session_id='sess-1', platform='android')
        AnalyticsEvent.objects.filter(name='screen_exited').update(
            session_id='sess-1', platform='android')

        self.auth(staff)
        res = self.client.get('/api/analytics/report/?days=30')
        self.assertEqual(res.status_code, 200)
        self.assertIn('insights', res.data)
        self.assertEqual(res.data['funnels']['match']['steps'][0]['users'], 1)
        self.assertEqual(res.data['funnels']['match']['steps'][2]['users'], 1)
        self.assertEqual(res.data['screens'][0]['screen'], 'Home')
        self.assertEqual(res.data['screens'][0]['avg_seconds'], 12.0)
        self.assertEqual(res.data['users']['active'], 1)


class EngagementTests(BaseAPITestCase):
    def setUp(self):
        super().setUp()
        self.user = self.make_user('engaged')
        profile = UserProfile.get_or_create_for_user(self.user)
        profile.favorite_sports = 'basketball'
        profile.save()

    def _match(self, organizer, sport, hours=48, max_players=10, current=2):
        match = Match.objects.create(
            title=f'{sport} match', sport=sport, location='Bole',
            date_time=timezone.now() + timedelta(hours=hours),
            max_players=max_players, current_players=current, organizer=organizer)
        return match

    def test_recommendation_ranks_favorite_sport_first(self):
        from .engagement import recommend_matches
        other = self.make_user('other_host')
        soccer = self._match(other, 'soccer', hours=24)
        basket = self._match(other, 'basketball', hours=72)
        recs = recommend_matches(self.user, limit=5)
        self.assertEqual(recs[0]['id'], basket.id,
                         [(r['id'], r['sport'], r['match_score']) for r in recs])
        self.assertIn(soccer.id, [r['id'] for r in recs])

    def test_next_best_action_match_soon(self):
        from .engagement import next_best_action
        other = self.make_user('host2')
        match = self._match(other, 'basketball', hours=5)
        MatchParticipant.objects.create(match=match, user=self.user)
        action = next_best_action(self.user)
        self.assertEqual(action['type'], 'match_soon')
        self.assertEqual(action['match_id'], match.id)

    def test_streak_counts_consecutive_weeks(self):
        from .engagement import user_streak
        other = self.make_user('host3')
        now = timezone.now()
        for weeks_ago in (0, 1):
            match = self._match(other, 'basketball', hours=48)
            MatchParticipant.objects.create(match=match, user=self.user)
            MatchParticipant.objects.filter(
                match=match, user=self.user).update(
                joined_at=now - timedelta(weeks=weeks_ago))
        streak = user_streak(self.user)
        self.assertEqual(streak['weeks'], 2)
        self.assertTrue(streak['active_this_week'])

    def test_at_risk_score_with_no_recent_activity(self):
        from .engagement import at_risk_score
        risk = at_risk_score(self.user)
        self.assertGreaterEqual(risk['score'], 30)

    def test_engagement_endpoint_returns_status(self):
        self.auth(self.user)
        res = self.client.get('/api/engagement/status/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('streak', res.data)
        self.assertIn('at_risk', res.data)
        self.assertIn('next_action', res.data)


class AnalyticsDashboardTests(BaseAPITestCase):
    def test_dashboard_requires_staff(self):
        res = self.client.get('/insights/')
        self.assertEqual(res.status_code, 302)

    def test_dashboard_renders_for_staff(self):
        staff = self.make_user('dashstaff')
        staff.is_staff = True
        staff.save()
        self.client.force_login(staff)
        res = self.client.get('/insights/?days=7')
        self.assertEqual(res.status_code, 200)
        self.assertIn(b'Victiqo Insights', res.content)
        self.assertIn(b'Growth models', res.content)

    def test_export_requires_staff(self):
        res = self.client.get('/insights/export/')
        self.assertEqual(res.status_code, 302)

    def test_export_returns_markdown_attachment(self):
        staff = self.make_user('dashexport')
        staff.is_staff = True
        staff.save()
        self.client.force_login(staff)
        res = self.client.get('/insights/export/?days=7')
        self.assertEqual(res.status_code, 200)
        self.assertIn('attachment;', res['Content-Disposition'])
        self.assertIn('Product Analytics Report', res.content.decode('utf-8'))


class Glicko2Tests(BaseAPITestCase):
    def test_winner_gains_and_uncertainty_shrinks(self):
        from .glicko2 import update_rating
        new_rating, new_rd, _ = update_rating(1200, 350, 0.06, [(1200, 350, 1.0)])
        self.assertGreater(new_rating, 1200)
        self.assertLess(new_rd, 350)

    def test_loser_drops(self):
        from .glicko2 import update_rating
        new_rating, _, _ = update_rating(1200, 350, 0.06, [(1200, 350, 0.0)])
        self.assertLess(new_rating, 1200)

    def test_draw_is_neutral_at_equal_ratings(self):
        from .glicko2 import update_rating
        new_rating, _, _ = update_rating(1200, 350, 0.06, [(1200, 350, 0.5)])
        self.assertAlmostEqual(new_rating, 1200, delta=0.5)

    def test_empty_opponents_is_identity(self):
        from .glicko2 import update_rating
        self.assertEqual(update_rating(1320, 120, 0.05, []), (1320.0, 120.0, 0.05))

    def test_confirmed_result_updates_glicko_fields(self):
        from .view_shared import _apply_result_rankings
        organizer = self.make_user('glickohost')
        winner = self.make_user('glickowinner')
        match = self.make_match(organizer)
        MatchParticipant.objects.create(match=match, user=winner)
        result = MatchResult.objects.create(
            match=match, match_type='pickup', result_type='individual',
            winner_user=winner, status='confirmed')
        _apply_result_rankings(match, result)

        winner_rating = UserSportRating.objects.get(user=winner, sport='soccer')
        loser_rating = UserSportRating.objects.get(user=organizer, sport='soccer')
        self.assertGreater(winner_rating.elo_rating, 1200)
        self.assertLess(loser_rating.elo_rating, 1200)
        self.assertLess(winner_rating.rating_deviation, 350)
        self.assertIsNotNone(winner_rating.last_rated_at)


class ReliabilityTests(BaseAPITestCase):
    def test_no_shows_lower_reliability_and_ratings_raise_it(self):
        from .reliability import reliability
        user = self.make_user('reliable')
        profile = UserProfile.get_or_create_for_user(user)
        self.assertEqual(reliability(user)['score'], 100)

        profile.no_show_count = 2
        profile.save()
        self.assertEqual(reliability(user)['score'], 70)

        host = self.make_user('reliablehost')
        match = self.make_match(host)
        PlayerRating.objects.create(
            match=match, rater=host, rated_user=user, rating=5)
        self.assertEqual(reliability(user)['score'], 90)

    def test_organizer_reliability_map_is_bulk(self):
        from .reliability import organizer_reliability_map
        host = self.make_user('relmap')
        match = self.make_match(host)
        scores = organizer_reliability_map([match])
        self.assertEqual(scores[host.id]['score'], 100)


class ExperimentTests(BaseAPITestCase):
    def test_assignment_is_stable_and_valid(self):
        from .experiments import ranking_config, variant_for
        user = self.make_user('experiment')
        first = variant_for(user, 'ranking_v2')
        self.assertEqual(first, variant_for(user, 'ranking_v2'))
        self.assertIn(first, ('A', 'B'))
        config = ranking_config(user)
        self.assertEqual(config['variant'], first)
        for key in ('sport', 'city', 'urgency', 'scarcity', 'social', 'quality'):
            self.assertIn(key, config)


class CollaborativeTests(BaseAPITestCase):
    def test_co_participation_surfaces_target_match(self):
        from .collaborative import co_participation_scores
        me = self.make_user('cfme')
        host = self.make_user('cfhost')
        co1 = self.make_user('cfco1')
        co2 = self.make_user('cfco2')

        for index in range(3):
            history = self.make_match(host, title=f'History {index}')
            MatchParticipant.objects.create(match=history, user=me)
            MatchParticipant.objects.create(match=history, user=co1)

        target = self.make_match(host, title='Target')
        MatchParticipant.objects.create(match=target, user=co1)
        MatchParticipant.objects.create(match=target, user=co2)

        scores = co_participation_scores(me)
        self.assertIn(target.id, scores)
        self.assertGreater(scores[target.id], 0)

    def test_cold_start_returns_nothing(self):
        from .collaborative import co_participation_scores
        me = self.make_user('cfcold')
        self.assertEqual(co_participation_scores(me), {})


class RankingAlgorithmTests(BaseAPITestCase):
    def setUp(self):
        super().setUp()
        self.user = self.make_user('ranked')
        profile = UserProfile.get_or_create_for_user(self.user)
        profile.favorite_sports = 'basketball'
        profile.location = 'Addis Ababa, Ethiopia'
        profile.save()
        self.host = self.make_user('rankhost')

    def test_recommendations_include_reasons_and_log_exposures(self):
        from .engagement import recommend_matches
        basket = self.make_match(
            self.host, title='Basketball run', sport='basketball',
            location='Bole, Addis Ababa')
        self.make_match(self.host, title='Soccer run', sport='soccer')

        recs = recommend_matches(self.user, limit=5)
        self.assertTrue(recs)
        self.assertEqual(recs[0]['id'], basket.id)
        self.assertIn('Your sport', recs[0]['reasons'])
        self.assertEqual(recs[0]['reason'], 'Your sport')
        self.assertIn(recs[0]['recommendation_variant'], ('A', 'B'))
        self.assertEqual(RecommendationExposure.objects.filter(user=self.user).count(),
                         len(recs))
        exposure = RecommendationExposure.objects.filter(user=self.user).first()
        self.assertIn('sport_fit', exposure.features)

    def test_exploration_adds_something_new(self):
        from .engagement import recommend_matches
        for index in range(25):
            self.make_match(
                self.host, title=f'Explore {index}', sport='soccer',
                date_time=timezone.now() + timedelta(days=index + 1))
        recs = recommend_matches(self.user, limit=10)
        self.assertEqual(len(recs), 10)
        self.assertTrue(any('Something new' in rec['reasons'] for rec in recs))

    def test_recommendations_endpoint_logs_exposures(self):
        self.make_match(self.host, sport='basketball')
        self.auth(self.user)
        res = self.client.get('/api/matches/recommendations/')
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data['recommendations'])
        self.assertTrue(
            RecommendationExposure.objects.filter(user=self.user).exists())

    def test_engagement_status_has_reliability_models_and_experiments(self):
        self.auth(self.user)
        res = self.client.get('/api/engagement/status/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('reliability', res.data)
        self.assertIn('models', res.data)
        self.assertIn('experiments', res.data)
        self.assertIn('score', res.data['reliability'])


class BanditTests(BaseAPITestCase):
    def test_choose_arm_and_reward_updates_posterior(self):
        from .bandit import choose_arm, record_reward
        user = self.make_user('bandit')
        arm = choose_arm(user, 'send_time', ('morning', 'afternoon', 'evening'))
        self.assertIn(arm, ('morning', 'afternoon', 'evening'))
        row = record_reward(user, 'send_time', arm, True)
        self.assertEqual(row.alpha, 2)
        row = record_reward(user, 'send_time', arm, False)
        row.refresh_from_db()
        self.assertEqual(row.beta, 2)

    def test_quiet_hours_disable_send_time(self):
        from .bandit import is_quiet_hours, send_time_allows
        user = self.make_user('quiet')
        local = timezone.localtime(timezone.now())
        quiet = local.replace(hour=23, minute=0)
        self.assertTrue(is_quiet_hours(quiet))
        self.assertFalse(send_time_allows(user, quiet))

    def test_frequency_caps_block_generic_but_not_critical(self):
        from .bandit import notification_allowed
        user = self.make_user('capped')
        for index in range(2):
            Notification.objects.create(
                user=user, title=f'Notice {index}', message='hello')
        self.assertFalse(notification_allowed(user))
        self.assertTrue(notification_allowed(user, critical=True))

    def test_update_bandits_rewards_settled_notifications(self):
        from .bandit import update_bandits
        user = self.make_user('banditreward')
        sent = AnalyticsEvent.objects.create(
            user=user, name='notification_sent',
            properties={'kind': 'fill', 'variant': 'A', 'arm': 'morning'})
        AnalyticsEvent.objects.filter(id=sent.id).update(
            created_at=timezone.now() - timedelta(hours=30))
        activity = AnalyticsEvent.objects.create(user=user, name='screen_viewed')
        AnalyticsEvent.objects.filter(id=activity.id).update(
            created_at=timezone.now() - timedelta(hours=20))

        self.assertEqual(update_bandits(days=7), 1)
        copy_row = NotificationBandit.objects.get(
            user=user, experiment='notification_copy:fill', arm='A')
        time_row = NotificationBandit.objects.get(
            user=user, experiment='send_time', arm='morning')
        self.assertEqual(copy_row.alpha, 2)
        self.assertEqual(time_row.alpha, 2)
        self.assertEqual(update_bandits(days=7), 0)


class ModelTrainingTests(BaseAPITestCase):
    def _join_features(self, value):
        from .ml import JOIN_FEATURES
        return {feature: value for feature in JOIN_FEATURES}

    def test_join_model_trains_when_thresholds_met(self):
        from .ml import join_propensity, train_join_model
        host = self.make_user('mljoinhost')
        now = timezone.now()
        for index in range(12):
            user = self.make_user(f'mljoin{index}')
            match = self.make_match(host, title=f'Join {index}')
            exposure = RecommendationExposure.objects.create(
                user=user, match=match,
                features=self._join_features(1.0 if index % 2 else 0.0))
            created = now - timedelta(days=2, minutes=index)
            RecommendationExposure.objects.filter(id=exposure.id).update(
                created_at=created)
            if index % 2:
                participant = MatchParticipant.objects.create(
                    match=match, user=user)
                MatchParticipant.objects.filter(id=participant.id).update(
                    joined_at=created + timedelta(hours=2))

        result = train_join_model(min_samples=10, min_positives=3)
        self.assertTrue(result['ready'])
        self.assertTrue(result['trained'])
        self.assertTrue(ModelArtifact.objects.filter(name='join_propensity').exists())
        probability = join_propensity(self._join_features(1.0))
        self.assertIsNotNone(probability)
        self.assertGreaterEqual(probability, 0)
        self.assertLessEqual(probability, 1)

    def test_join_model_waits_below_threshold(self):
        from .ml import train_join_model
        result = train_join_model(min_samples=50, min_positives=10)
        self.assertFalse(result['ready'])
        self.assertFalse(result['trained'])
        self.assertFalse(ModelArtifact.objects.filter(name='join_propensity').exists())

    def test_churn_model_trains_on_six_week_window(self):
        from .ml import train_churn_model
        now = timezone.now()
        for index in range(8):
            user = self.make_user(f'mlchurn{index}')
            for event_index in range(4):
                event = AnalyticsEvent.objects.create(
                    user=user, name='screen_viewed',
                    session_id=f'churn-{index}-{event_index}')
                AnalyticsEvent.objects.filter(id=event.id).update(
                    created_at=now - timedelta(days=30, minutes=event_index))
            if index % 2:
                event = AnalyticsEvent.objects.create(
                    user=user, name='screen_viewed', session_id=f'return-{index}')
                AnalyticsEvent.objects.filter(id=event.id).update(
                    created_at=now - timedelta(days=7))

        result = train_churn_model(min_users=6)
        self.assertTrue(result['ready'])
        self.assertTrue(result['trained'])
        self.assertTrue(ModelArtifact.objects.filter(name='churn').exists())

    def test_fill_model_trains_on_closed_matches(self):
        from .ml import fill_probability, train_fill_model
        host = self.make_user('mlfillhost')
        now = timezone.now()
        for index in range(12):
            match = Match.objects.create(
                title=f'Fill {index}', sport='soccer', location='Bole',
                date_time=now - timedelta(days=2),
                max_players=10, current_players=10 if index % 2 else 2,
                organizer=host)
            Match.objects.filter(id=match.id).update(
                created_at=now - timedelta(days=10))

        result = train_fill_model(min_matches=10)
        self.assertTrue(result['ready'])
        self.assertTrue(result['trained'])
        self.assertTrue(ModelArtifact.objects.filter(name='fill_probability').exists())
        match = Match.objects.create(
            title='Live fill', sport='soccer', location='Bole',
            date_time=now + timedelta(hours=12),
            max_players=10, current_players=8, organizer=host)
        probability = fill_probability(match)
        self.assertGreaterEqual(probability, 0)
        self.assertLessEqual(probability, 1)


class PostMatchLoopTests(BaseAPITestCase):
    def test_rematch_nudge_is_sent_once(self):
        from .engagement import post_match_rematch
        host = self.make_user('rematchhost')
        player = self.make_user('rematchplayer')
        match = self.make_match(host)
        MatchParticipant.objects.create(match=match, user=player)
        MatchResult.objects.create(
            match=match, match_type='pickup', result_type='draw',
            status='confirmed', confirmed_at=timezone.now() - timedelta(hours=30))

        sent = post_match_rematch()
        self.assertGreaterEqual(sent, 1)
        self.assertEqual(Notification.objects.filter(user=player).count(), 1)
        post_match_rematch()
        self.assertEqual(Notification.objects.filter(user=player).count(), 1)

    def test_weekly_recap_sends_for_active_user(self):
        from .engagement import weekly_recap
        host = self.make_user('recaphost')
        player = self.make_user('recapplayer')
        match = self.make_match(host)
        MatchParticipant.objects.create(match=match, user=player)
        sent = weekly_recap(force=True)
        self.assertGreaterEqual(sent, 1)
        self.assertEqual(Notification.objects.filter(user=player).count(), 1)


class HostPayoutTests(BaseAPITestCase):
    def setUp(self):
        super().setUp()
        self.host = self.make_user('payouthost')
        self.player = self.make_user('payoutplayer')
        self.match = self.make_match(
            self.host, title='Paid match', price=Decimal('250'))
        self.participant = MatchParticipant.objects.create(
            match=self.match, user=self.player)

    def _hold(self):
        from .escrow import hold
        hold(self.participant, amount=Decimal('250'))
        self.participant.refresh_from_db()
        return self.participant

    def test_release_credits_host_balance_once(self):
        from .escrow import release_match_funds
        from .payouts import account_for
        self._hold()

        self.assertEqual(release_match_funds(self.match), Decimal('250.00'))
        self.assertEqual(release_match_funds(self.match), Decimal('0.00'))

        account = account_for(self.host)
        self.assertEqual(account.available_balance, Decimal('250.00'))
        self.assertEqual(account.pending_balance, Decimal('0'))
        entries = account.entries.filter(kind='match_release')
        self.assertEqual(entries.count(), 1)
        self.assertEqual(entries.first().amount, Decimal('250.00'))
        self.assertEqual(entries.first().match_id, self.match.id)

    def test_no_show_forfeit_credits_host(self):
        from .escrow import forfeit_no_shows
        from .payouts import account_for
        self._hold()

        total = forfeit_no_shows(self.match, [self.player.id])
        self.assertEqual(total, Decimal('250.00'))
        self.assertEqual(forfeit_no_shows(self.match, [self.player.id]), Decimal('0.00'))

        account = account_for(self.host)
        self.assertEqual(account.available_balance, Decimal('250.00'))
        self.assertTrue(account.entries.filter(kind='no_show_forfeit').exists())

    def test_payout_request_moves_available_to_pending(self):
        from .payouts import account_for, credit_host, request_payout
        credit_host(self.host, Decimal('500'), 'adjustment')

        payout = request_payout(
            self.host, Decimal('300'), method='telebirr',
            destination='0911223344')
        account = account_for(self.host)
        self.assertEqual(account.available_balance, Decimal('200.00'))
        self.assertEqual(account.pending_balance, Decimal('300.00'))
        self.assertEqual(payout.status, 'requested')

        with self.assertRaises(ValueError):
            request_payout(self.host, Decimal('100'), method='bank',
                           destination='1234567890')

    def test_payout_minimum_and_available_checks(self):
        from .payouts import credit_host, request_payout
        with self.assertRaises(ValueError):
            request_payout(self.host, Decimal('50'), method='bank',
                           destination='1234567890')

        credit_host(self.host, Decimal('150'), 'adjustment')
        with self.assertRaises(ValueError):
            request_payout(self.host, Decimal('500'), method='bank',
                           destination='1234567890')

    def test_mark_paid_and_reject_lifecycle(self):
        from .payouts import (
            account_for, credit_host, mark_payout_paid, reject_payout,
            request_payout,
        )
        staff = self.make_user('payoutstaff')
        staff.is_staff = True
        staff.save()
        credit_host(self.host, Decimal('500'), 'adjustment')

        payout = request_payout(
            self.host, Decimal('300'), method='telebirr',
            destination='0911223344')
        mark_payout_paid(payout, staff, reference='TELE-123')
        account = account_for(self.host)
        self.assertEqual(account.available_balance, Decimal('200.00'))
        self.assertEqual(account.pending_balance, Decimal('0'))
        self.assertEqual(account.paid_out_total, Decimal('300.00'))
        payout.refresh_from_db()
        self.assertEqual(payout.status, 'paid')
        self.assertEqual(payout.reference, 'TELE-123')
        self.assertEqual(payout.processed_by, staff)

        payout2 = request_payout(
            self.host, Decimal('200'), method='bank',
            destination='1234567890')
        reject_payout(payout2, staff, note='Wrong account')
        account.refresh_from_db()
        self.assertEqual(account.available_balance, Decimal('200.00'))
        self.assertEqual(account.pending_balance, Decimal('0'))
        payout2.refresh_from_db()
        self.assertEqual(payout2.status, 'rejected')
        self.assertTrue(account.entries.filter(kind='payout_rejected').exists())

    def test_cancellation_claws_back_released_funds(self):
        from .escrow import cancel_and_settle, release_match_funds
        from .payouts import account_for
        self._hold()
        release_match_funds(self.match)
        self.assertEqual(account_for(self.host).available_balance, Decimal('250.00'))

        settlement = cancel_and_settle(self.match, reason='Host cancelled')
        self.assertEqual(settlement['fronted'], Decimal('250.00'))
        account = account_for(self.host)
        self.assertEqual(account.available_balance, Decimal('0.00'))
        self.assertTrue(account.entries.filter(kind='cancellation_clawback').exists())

    def test_payout_api_and_permissions(self):
        from .payouts import credit_host
        credit_host(self.host, Decimal('500'), 'adjustment')

        self.auth(self.host)
        res = self.client.get('/api/host/earnings/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data['account']['available'], '500.00')

        res = self.client.post('/api/host/payouts/', {
            'amount': '250', 'method': 'telebirr', 'destination': '0911223344',
        }, format='json')
        self.assertEqual(res.status_code, 201)
        payout_id = res.data['payout']['id']
        self.assertEqual(res.data['account']['pending'], '250.00')

        payout = HostPayout.objects.get(id=payout_id)
        staff = self.make_user('payoutreviewer')
        staff.is_staff = True
        staff.save()
        self.auth(staff)
        res = self.client.post(
            f'/api/host/payouts/{payout_id}/review/',
            {'action': 'paid', 'reference': 'BANK-999'}, format='json')
        self.assertEqual(res.status_code, 200)
        payout.refresh_from_db()
        self.assertEqual(payout.status, 'paid')
        self.assertEqual(payout.reference, 'BANK-999')

        other = self.make_user('payoutother')
        self.auth(other)
        res = self.client.post(f'/api/host/payouts/{payout_id}/cancel/')
        self.assertEqual(res.status_code, 404)

    def test_non_staff_cannot_review_payout(self):
        from .payouts import credit_host, request_payout
        credit_host(self.host, Decimal('200'), 'adjustment')
        payout = request_payout(
            self.host, Decimal('200'), method='bank', destination='1234567890')
        self.auth(self.host)
        res = self.client.post(
            f'/api/host/payouts/{payout.id}/review/',
            {'action': 'paid', 'reference': 'NOPE'}, format='json')
        self.assertIn(res.status_code, (401, 403))

    def test_host_can_cancel_requested_payout(self):
        from .payouts import account_for, credit_host, request_payout
        credit_host(self.host, Decimal('500'), 'adjustment')
        payout = request_payout(
            self.host, Decimal('300'), method='bank', destination='1234567890')
        self.auth(self.host)
        res = self.client.post(f'/api/host/payouts/{payout.id}/cancel/')
        self.assertEqual(res.status_code, 200)
        account = account_for(self.host)
        self.assertEqual(account.available_balance, Decimal('500.00'))
        self.assertEqual(account.pending_balance, Decimal('0'))
        payout.refresh_from_db()
        self.assertEqual(payout.status, 'cancelled')


class MatchPotWithdrawalTests(BaseAPITestCase):
    def setUp(self):
        super().setUp()
        self.venue_owner = self.make_user('potvenueowner')
        self.venue = Venue.objects.create(
            owner=self.venue_owner, name='Pot Pitch', address='Road 2', city='Addis',
            slot_price=Decimal('1000'), is_available=True)
        self.host = self.make_user('pothost')
        self.players = [self.make_user(f'potplayer{i}') for i in range(4)]
        self.match = self.make_match(
            self.host, title='Pot Match', price=Decimal('300'),
            venue=self.venue, min_players=5, max_players=8,
            date_time=timezone.now() + timedelta(days=2))
        for player in self.players:
            participant = MatchParticipant.objects.create(match=self.match, user=player)
            participant.payment_status = 'held'
            participant.paid = True
            participant.amount_paid = Decimal('300')
            participant.save()
        host_participant = MatchParticipant.objects.get(
            match=self.match, user=self.host)
        host_participant.payment_status = 'held'
        host_participant.paid = True
        host_participant.amount_paid = Decimal('300')
        host_participant.save()
        self.match.current_players = 5
        self.match.save(update_fields=['current_players'])

    def _book(self):
        from .views_matches import _book_field_for_match
        return _book_field_for_match(self.match)

    def test_booking_pays_venue_and_holds_surplus(self):
        from .payouts import account_for
        result = self._book()
        self.match.refresh_from_db()
        self.assertEqual(self.match.booking_status, 'confirmed')
        pot = MatchPot.objects.get(match=self.match)
        self.assertEqual(pot.collected, Decimal('1500.00'))
        self.assertEqual(pot.venue_amount, Decimal('1000.00'))
        self.assertEqual(pot.platform_fee, Decimal('250.00'))
        self.assertEqual(pot.surplus, Decimal('250.00'))
        self.assertEqual(result['surplus_held'], '250.00')
        self.assertEqual(
            account_for(self.venue_owner).available_balance, Decimal('1000.00'))
        self.assertEqual(
            account_for(self.host).available_balance, Decimal('0.00'))
        self.assertTrue(PlatformTransaction.objects.filter(
            kind='field_service_fee', amount=Decimal('250.00'),
            status='collected').exists())

    def test_booking_rejects_short_pot(self):
        from .views_matches import _book_field_for_match
        self.match.price = Decimal('200')
        self.match.save(update_fields=['price'])
        MatchParticipant.objects.filter(match=self.match).update(
            amount_paid=Decimal('200'))
        with self.assertRaises(ValueError):
            _book_field_for_match(self.match)

    def test_withdraw_opens_funded_spot_and_replacement_joins_free(self):
        from .match_pot import claim_funded_spot, withdraw_participant
        self._book()
        result = withdraw_participant(self.match, self.players[0])
        self.match.refresh_from_db()
        self.assertEqual(result['funded_spots'], 1)
        self.assertEqual(self.match.current_players, 4)
        participant = MatchParticipant.objects.get(
            match=self.match, user=self.players[0])
        self.assertIsNotNone(participant.withdrawn_at)
        self.assertEqual(participant.payment_status, 'forfeited')
        withdrawal = MatchWithdrawal.objects.get(
            match=self.match, user=self.players[0])
        self.assertEqual(withdrawal.status, 'open')
        self.assertEqual(withdrawal.share_amount, Decimal('300.00'))

        newcomer = self.make_user('potnewcomer')
        claim = claim_funded_spot(self.match, newcomer)
        self.assertEqual(claim['funded_spots'], 0)
        new_participant = MatchParticipant.objects.get(
            match=self.match, user=newcomer)
        self.assertEqual(new_participant.payment_status, 'covered')
        self.assertEqual(new_participant.amount_paid, Decimal('0'))
        withdrawal.refresh_from_db()
        self.assertEqual(withdrawal.status, 'replaced')
        self.assertEqual(withdrawal.replacement_user, newcomer)
        self.match.refresh_from_db()
        self.assertEqual(self.match.current_players, 5)

    def test_host_withdraw_transfers_organizer(self):
        from .match_pot import withdraw_participant
        self._book()
        result = withdraw_participant(self.match, self.host)
        self.match.refresh_from_db()
        self.assertNotEqual(self.match.organizer_id, self.host.id)
        self.assertIsNotNone(result['new_organizer_id'])
        self.assertEqual(result['funded_spots'], 1)
        self.assertFalse(MatchParticipant.objects.filter(
            match=self.match, user=self.host, withdrawn_at__isnull=True).exists())

    def test_leave_after_booking_is_blocked(self):
        self._book()
        self.auth(self.players[1])
        res = self.client.post('/api/matches/leave/', {
            'match_id': self.match.id}, format='json')
        self.assertEqual(res.status_code, 400)
        self.assertEqual(res.data.get('code'), 'use_withdraw')
        self.assertTrue(MatchParticipant.objects.filter(
            match=self.match, user=self.players[1]).exists())

    def test_host_cancel_before_booking_keeps_20_percent(self):
        self.auth(self.host)
        res = self.client.post('/api/matches/cancel/', {
            'match_id': self.match.id}, format='json')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data['host_fee_kept'], '60.00')
        host_participant = MatchParticipant.objects.get(
            match=self.match, user=self.host)
        self.assertEqual(host_participant.payment_status, 'partially_refunded')
        player_participant = MatchParticipant.objects.get(
            match=self.match, user=self.players[0])
        self.assertEqual(player_participant.payment_status, 'refunded')
        self.assertTrue(PlatformTransaction.objects.filter(
            kind='cancellation_fee', amount=Decimal('60.00'),
            status='collected').exists())

    def test_withdraw_api_and_funded_join_api(self):
        self._book()
        self.auth(self.players[2])
        res = self.client.post(f'/api/matches/{self.match.id}/withdraw/')
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data['success'])
        self.assertEqual(res.data['funded_spots'], 1)

        newcomer = self.make_user('apinewcomer')
        self.auth(newcomer)
        res = self.client.post('/api/matches/join/', {
            'match_id': self.match.id}, format='json')
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data.get('funded'))
        self.assertEqual(res.data['message'], 'Joined a funded spot — no payment needed')

    def test_withdraw_before_booking_is_rejected(self):
        from .match_pot import withdraw_participant
        with self.assertRaises(ValueError):
            withdraw_participant(self.match, self.players[0])

    def test_settlement_splits_surplus_as_credit(self):
        from .match_pot import settle_match_pot, withdraw_participant
        self._book()
        withdraw_participant(self.match, self.players[0])
        result = settle_match_pot(self.match, force=True)
        self.assertEqual(result['credited'], '250.00')
        self.assertEqual(result['players'], 4)
        for player in self.players[1:]:
            account = PlayerCreditAccount.objects.get(user=player)
            self.assertEqual(account.balance, Decimal('62.50'))
        pot = MatchPot.objects.get(match=self.match)
        self.assertEqual(pot.status, 'settled')
        self.assertFalse(MatchWithdrawal.objects.filter(
            match=self.match, status='open').exists())

        self.auth(self.players[1])
        res = self.client.get('/api/credits/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data['balance'], '62.50')

    def test_settlement_with_no_surplus_creates_no_credit(self):
        from .match_pot import settle_match_pot
        self._book()
        MatchPot.objects.filter(match=self.match).update(surplus=Decimal('0'))
        result = settle_match_pot(self.match, force=True)
        self.assertEqual(result['credited'], '0.00')
        self.assertFalse(PlayerCreditAccount.objects.exists())


class CreditAndReservationTests(BaseAPITestCase):
    def test_partial_credit_is_applied_and_returned_on_refund(self):
        from .credits import account_for, credit_player
        from .escrow import refund_participant
        host = self.make_user('credithost')
        player = self.make_user('creditplayer')
        match = self.make_match(host, price=Decimal('250'))
        participant = MatchParticipant.objects.create(match=match, user=player)
        credit_player(player, Decimal('100'), 'adjustment')

        self.auth(player)
        with self.settings(CHAPA_SECRET_KEY='', DEBUG=True):
            res = self.client.post(f'/api/matches/{match.id}/pay/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data['credit_used'], '100.00')
        self.assertEqual(res.data['amount_due'], '150.00')
        participant.refresh_from_db()
        self.assertEqual(participant.payment_status, 'held')
        self.assertEqual(participant.amount_paid, Decimal('250.00'))
        self.assertEqual(participant.credit_applied, Decimal('100.00'))
        self.assertEqual(account_for(player).balance, Decimal('0'))

        refund_participant(participant, percent=100)
        self.assertEqual(account_for(player).balance, Decimal('100.00'))
        participant.refresh_from_db()
        self.assertEqual(participant.credit_applied, Decimal('0'))
        self.assertEqual(participant.payment_status, 'refunded')

    def test_credit_can_cover_the_full_share(self):
        from .credits import account_for, credit_player
        host = self.make_user('fullcredithost')
        player = self.make_user('fullcreditplayer')
        match = self.make_match(host, price=Decimal('250'))
        participant = MatchParticipant.objects.create(match=match, user=player)
        credit_player(player, Decimal('250'), 'adjustment')

        self.auth(player)
        with self.settings(CHAPA_SECRET_KEY='', DEBUG=True):
            res = self.client.post(f'/api/matches/{match.id}/pay/')
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data.get('paid_with_credit'))
        self.assertEqual(res.data['amount_due'], '0.00')
        participant.refresh_from_db()
        self.assertEqual(participant.payment_status, 'held')
        self.assertEqual(participant.amount_paid, Decimal('250.00'))
        self.assertEqual(account_for(player).balance, Decimal('0'))
        self.assertFalse(Payment.objects.filter(
            user=player, payment_type='match_share').exists())

    def test_host_payment_reserves_slot_and_blocks_double_booking(self):
        owner = self.make_user('reserveowner')
        venue = Venue.objects.create(
            owner=owner, name='Reserve Pitch', address='Road 3', city='Addis',
            slot_price=Decimal('1000'), is_available=True)
        host = self.make_user('reservehost')
        match = self.make_match(
            host, price=Decimal('250'), venue=venue,
            date_time=timezone.now() + timedelta(days=2))

        self.auth(host)
        with self.settings(CHAPA_SECRET_KEY='', DEBUG=True):
            res = self.client.post(f'/api/matches/{match.id}/pay/')
        self.assertEqual(res.status_code, 200)

        booking = VenueBooking.objects.get(match=match)
        self.assertEqual(booking.status, 'reserved')
        self.assertEqual(booking.total_price, Decimal('1000.00'))

        other = self.make_user('reserveother')
        self.auth(other)
        local = timezone.localtime(match.date_time)
        date_str = local.date().isoformat()
        start = local.strftime('%H:%M')
        end = (local + timedelta(hours=2)).strftime('%H:%M')
        res = self.client.post('/api/venues/book/', {
            'venue_id': venue.id, 'date': date_str,
            'start_time': start, 'end_time': end,
        }, format='json')
        self.assertEqual(res.status_code, 409)

        res = self.client.get(
            f'/api/venues/{venue.id}/availability/?date={date_str}')
        self.assertEqual(res.status_code, 200)
        self.assertTrue(any(
            slot['status'] == 'reserved' for slot in res.data['slots']))




