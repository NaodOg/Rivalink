from django.contrib import admin

from .models import ModelArtifact, NotificationBandit, RecommendationExposure, UserSportRating


@admin.register(RecommendationExposure)
class RecommendationExposureAdmin(admin.ModelAdmin):
    list_display = ('user', 'match', 'surface', 'variant', 'score', 'created_at')
    list_filter = ('surface', 'variant')
    search_fields = ('user__username', 'match__title')


@admin.register(ModelArtifact)
class ModelArtifactAdmin(admin.ModelAdmin):
    list_display = ('name', 'samples', 'trained_at')


@admin.register(NotificationBandit)
class NotificationBanditAdmin(admin.ModelAdmin):
    list_display = ('user', 'experiment', 'arm', 'alpha', 'beta', 'updated_at')
    list_filter = ('experiment', 'arm')


@admin.register(UserSportRating)
class UserSportRatingAdmin(admin.ModelAdmin):
    list_display = ('user', 'sport', 'elo_rating', 'rating_deviation', 'matches_played')
    list_filter = ('sport',)
    search_fields = ('user__username',)
