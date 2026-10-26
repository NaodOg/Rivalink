from django.urls import path
from .views_auth import (
    health_check, signup, login, logout, update_profile, upload_profile_image,
)
from .views_matches import (
    create_match, get_matches, get_my_matches, join_match, get_match_details,
    leave_match, cancel_match, get_match_history, search_matches,
    get_match_chat, send_match_chat, edit_match,
    match_ratings, match_result, get_match_recommendations,
    confirm_match_result, mark_match_payments, pay_match_share,
    request_venue_booking, confirm_venue_booking,
)
from .views_teams import (
    create_team, get_my_teams, get_teams_seeking_players, join_team, leave_team,
    get_team_members, remove_team_member, update_member_role,
    get_team_join_requests, handle_join_request, request_to_join_team,
    get_team_chat, send_team_chat,
)
from .views_leagues import (
    get_leagues, get_my_leagues, create_league, edit_league, delete_league,
    join_league, get_league_details, start_league, cancel_league, remove_league_team,
    record_fixture_result, reschedule_fixture, schedule_fixture,
)
from .views_venues import (
    create_venue, list_venues, get_venue, get_my_venues, update_venue, delete_venue,
    book_venue, get_venue_bookings, update_venue_booking, rate_venue,
    venue_schedule, venue_revenue, venue_availability,
)
from .views_referees import (
    create_referee_profile, get_referee_profile, list_referees,
    book_referee, list_referee_bookings, update_booking_status, rate_referee,
)
from .views_tournaments import (
    create_tournament, list_tournaments, get_tournament, get_my_tournaments,
    edit_tournament, delete_tournament, register_team_tournament, start_tournament,
    update_match_result,
)
from .views_social import (
    get_notifications, mark_notifications_read, user_ratings, get_user_stats,
    manage_favorites, check_favorite, get_conversations, get_messages,
    get_individual_rankings, get_team_rankings, get_user_elo, get_user_form,
    create_report, toggle_block, register_device, unregister_device, run_reminders,
    social_me, follow_toggle, list_following, list_followers, list_teammates,
    list_referrals, send_phone_code, verify_phone, phone_status,
)
from .payment_views import (
    initialize_premium_payment, initialize_venue_booking_payment, payment_webhook,
    payment_status, get_my_payments
)
from .revenue_views import revenue_summary, my_transactions
from .analytics_views import ingest_analytics, analytics_report
from .engagement_views import engagement
from .auth_views import (
    change_password, logout_all, password_reset_request, password_reset_confirm,
)

urlpatterns = [
    path('health/', health_check, name='health_check'),
    path('auth/signup/', signup, name='signup'),
    path('auth/login/', login, name='login'),
    path('auth/logout/', logout, name='logout'),
    path('auth/logout-all/', logout_all, name='logout_all'),
    path('auth/password/change/', change_password, name='change_password'),
    path('auth/password/reset/request/', password_reset_request, name='password_reset_request'),
    path('auth/password/reset/confirm/', password_reset_confirm, name='password_reset_confirm'),
    path('auth/profile/', update_profile, name='update_profile'),
    path('auth/profile/image/', upload_profile_image, name='upload_profile_image'),
    path('teams/create/', create_team, name='create_team'),
    path('teams/my/', get_my_teams, name='get_my_teams'),
    path('teams/seeking/', get_teams_seeking_players, name='get_teams_seeking_players'),
    path('teams/join/', join_team, name='join_team'),
    path('teams/leave/', leave_team, name='leave_team'),
    path('teams/<int:team_id>/members/', get_team_members, name='get_team_members'),
    path('teams/remove-member/', remove_team_member, name='remove_team_member'),
    path('teams/update-role/', update_member_role, name='update_member_role'),
    path('teams/<int:team_id>/requests/', get_team_join_requests, name='get_team_join_requests'),
    path('teams/handle-request/', handle_join_request, name='handle_join_request'),
    path('teams/request-join/', request_to_join_team, name='request_to_join_team'),
    path('matches/create/', create_match, name='create_match'),
    path('matches/', get_matches, name='get_matches'),
    path('matches/search/', search_matches, name='search_matches'),
    path('matches/my/', get_my_matches, name='get_my_matches'),
    path('matches/history/', get_match_history, name='get_match_history'),
    path('matches/join/', join_match, name='join_match'),
    path('matches/leave/', leave_match, name='leave_match'),
    path('matches/cancel/', cancel_match, name='cancel_match'),
    path('matches/<int:match_id>/', get_match_details, name='get_match_details'),
    path('notifications/', get_notifications, name='get_notifications'),
    path('notifications/read/', mark_notifications_read, name='mark_notifications_read'),
    path('matches/<int:match_id>/chat/', get_match_chat, name='get_match_chat'),
    path('matches/<int:match_id>/chat/send/', send_match_chat, name='send_match_chat'),
    path('teams/<int:team_id>/chat/', get_team_chat, name='get_team_chat'),
    path('teams/<int:team_id>/chat/send/', send_team_chat, name='send_team_chat'),
    path('matches/<int:match_id>/edit/', edit_match, name='edit_match'),
    path('leagues/', get_leagues, name='get_leagues'),
    path('leagues/my/', get_my_leagues, name='get_my_leagues'),
    path('leagues/create/', create_league, name='create_league'),
    path('leagues/<int:league_id>/edit/', edit_league, name='edit_league'),
    path('leagues/<int:league_id>/delete/', delete_league, name='delete_league'),
    path('leagues/join/', join_league, name='join_league'),
    path('leagues/<int:league_id>/', get_league_details, name='get_league_details'),
    path('leagues/<int:league_id>/start/', start_league, name='start_league'),
    path('leagues/<int:league_id>/cancel/', cancel_league, name='cancel_league'),
    path('leagues/<int:league_id>/remove-team/', remove_league_team, name='remove_league_team'),
    path('leagues/fixtures/<int:fixture_id>/result/', record_fixture_result, name='record_fixture_result'),
    path('leagues/fixtures/<int:fixture_id>/reschedule/', reschedule_fixture, name='reschedule_fixture'),
    path('leagues/fixtures/<int:fixture_id>/schedule/', schedule_fixture, name='schedule_fixture'),
    path('matches/<int:match_id>/ratings/', match_ratings, name='match_ratings'),
    path('matches/<int:match_id>/result/', match_result, name='match_result'),
    path('matches/<int:match_id>/result/confirm/', confirm_match_result, name='confirm_match_result'),
    path('matches/<int:match_id>/payments/', mark_match_payments, name='mark_match_payments'),
    path('matches/<int:match_id>/pay/', pay_match_share, name='pay_match_share'),
    path('matches/<int:match_id>/booking-request/', request_venue_booking, name='request_venue_booking'),
    path('matches/<int:match_id>/booking-confirm/', confirm_venue_booking, name='confirm_venue_booking'),
    path('users/<int:user_id>/ratings/', user_ratings, name='user_ratings'),
    path('users/<int:user_id>/stats/', get_user_stats, name='get_user_stats'),
    path('favorites/<str:favorite_type>/<int:object_id>/', manage_favorites, name='manage_favorites'),
    path('favorites/<str:favorite_type>/<int:object_id>/check/', check_favorite, name='check_favorite'),
    path('matches/recommendations/', get_match_recommendations, name='get_match_recommendations'),
    path('messages/conversations/', get_conversations, name='get_conversations'),
    path('messages/<int:user_id>/', get_messages, name='get_messages'),
    # Referee endpoints
    path('referees/', list_referees, name='list_referees'),
    path('referees/profile/', create_referee_profile, name='create_referee_profile'),
    path('referees/profile/<int:user_id>/', get_referee_profile, name='get_referee_profile'),
    path('referees/book/', book_referee, name='book_referee'),
    path('referees/bookings/', list_referee_bookings, name='list_referee_bookings'),
    path('referees/bookings/<int:booking_id>/', update_booking_status, name='update_booking_status'),
    path('referees/bookings/<int:booking_id>/rate/', rate_referee, name='rate_referee'),
    # Venue endpoints
    path('venues/', list_venues, name='list_venues'),
    path('venues/create/', create_venue, name='create_venue'),
    path('venues/my/', get_my_venues, name='get_my_venues'),
    path('venues/<int:venue_id>/', get_venue, name='get_venue'),
    path('venues/<int:venue_id>/update/', update_venue, name='update_venue'),
    path('venues/<int:venue_id>/delete/', delete_venue, name='delete_venue'),
    path('venues/<int:venue_id>/rate/', rate_venue, name='rate_venue'),
    path('venues/book/', book_venue, name='book_venue'),
    path('venues/bookings/', get_venue_bookings, name='get_venue_bookings'),
    path('venues/bookings/<int:booking_id>/', update_venue_booking, name='update_venue_booking'),
    path('venues/revenue/', venue_revenue, name='venue_revenue'),
    path('venues/<int:venue_id>/schedule/', venue_schedule, name='venue_schedule'),
    path('venues/<int:venue_id>/availability/', venue_availability, name='venue_availability'),
    # Tournament endpoints
    path('tournaments/', list_tournaments, name='list_tournaments'),
    path('tournaments/my/', get_my_tournaments, name='get_my_tournaments'),
    path('tournaments/create/', create_tournament, name='create_tournament'),
    path('tournaments/<int:tournament_id>/edit/', edit_tournament, name='edit_tournament'),
    path('tournaments/<int:tournament_id>/delete/', delete_tournament, name='delete_tournament'),
    path('tournaments/<int:tournament_id>/', get_tournament, name='get_tournament'),
    path('tournaments/<int:tournament_id>/start/', start_tournament, name='start_tournament'),
    path('tournaments/register/', register_team_tournament, name='register_team_tournament'),
    path('tournaments/matches/<int:match_id>/result/', update_match_result, name='update_match_result'),
    # Ranking endpoints
    path('rankings/individual/', get_individual_rankings, name='get_individual_rankings'),
    path('rankings/teams/', get_team_rankings, name='get_team_rankings'),
    path('rankings/user/<int:user_id>/', get_user_elo, name='get_user_elo'),
    path('users/<int:user_id>/form/', get_user_form, name='get_user_form'),
    # Trust & safety
    path('reports/create/', create_report, name='create_report'),
    path('blocks/toggle/', toggle_block, name='toggle_block'),
    # Push devices + reminders
    path('devices/register/', register_device, name='register_device'),
    path('devices/unregister/', unregister_device, name='unregister_device'),
    path('tasks/run-reminders/', run_reminders, name='run_reminders'),
    # Social graph
    path('social/me/', social_me, name='social_me'),
    path('social/follow/', follow_toggle, name='follow_toggle'),
    path('social/following/', list_following, name='list_following'),
    path('social/followers/', list_followers, name='list_followers'),
    path('social/teammates/', list_teammates, name='list_teammates'),
    path('social/referrals/', list_referrals, name='list_referrals'),
    # Phone verification
    path('auth/phone/send-code/', send_phone_code, name='send_phone_code'),
    path('auth/phone/verify/', verify_phone, name='verify_phone'),
    path('auth/phone/status/', phone_status, name='phone_status'),
    # Payment endpoints
    path('payments/initialize/', initialize_premium_payment, name='initialize_premium_payment'),
    path('payments/venue/initialize/', initialize_venue_booking_payment,
         name='initialize_venue_booking_payment'),
    path('payments/webhook/', payment_webhook, name='payment_webhook'),
    path('payments/status/', payment_status, name='payment_status'),
    path('payments/history/', get_my_payments, name='get_my_payments'),
    # Revenue / monetization
    path('revenue/summary/', revenue_summary, name='revenue_summary'),
    path('revenue/me/', my_transactions, name='my_transactions'),
    # Product analytics
    path('analytics/events/', ingest_analytics, name='ingest_analytics'),
    path('analytics/report/', analytics_report, name='analytics_report'),
    path('engagement/status/', engagement, name='engagement_status'),
]

