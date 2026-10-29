from django.contrib import admin, messages

from .models import (
    HostAccount, HostLedgerEntry, HostPayout, MatchPot, MatchWithdrawal,
    ModelArtifact, NotificationBandit, PlayerCreditAccount, PlayerCreditEntry,
    RecommendationExposure, UserSportRating,
)
from .payouts import mark_payout_paid, reject_payout


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


@admin.register(HostAccount)
class HostAccountAdmin(admin.ModelAdmin):
    list_display = ('user', 'available_balance', 'pending_balance', 'paid_out_total',
                    'updated_at')
    search_fields = ('user__username', 'user__email')


@admin.register(HostLedgerEntry)
class HostLedgerEntryAdmin(admin.ModelAdmin):
    list_display = ('account', 'kind', 'amount', 'match', 'payout', 'created_at')
    list_filter = ('kind',)
    search_fields = ('account__user__username', 'note')
    readonly_fields = ('account', 'amount', 'kind', 'match', 'payout', 'note', 'created_at')


@admin.action(description='Mark selected payouts paid (uses each row’s reference)')
def _mark_paid(modeladmin, request, queryset):
    done = skipped = 0
    for payout in queryset.filter(status__in=('requested', 'processing')):
        try:
            mark_payout_paid(
                payout, request.user,
                reference=payout.reference or f'ADMIN-{payout.id}',
                note=payout.admin_note or 'Marked paid from Django admin',
            )
            done += 1
        except ValueError:
            skipped += 1
    messages.success(request, f'{done} payout(s) marked paid, {skipped} skipped.')


@admin.action(description='Reject selected payouts (returns funds to available)')
def _reject(modeladmin, request, queryset):
    done = skipped = 0
    for payout in queryset.filter(status__in=('requested', 'processing')):
        try:
            reject_payout(payout, request.user,
                          note=payout.admin_note or 'Rejected from Django admin')
            done += 1
        except ValueError:
            skipped += 1
    messages.success(request, f'{done} payout(s) rejected, {skipped} skipped.')


@admin.register(HostPayout)
class HostPayoutAdmin(admin.ModelAdmin):
    list_display = ('user', 'amount', 'method', 'status', 'reference', 'requested_at',
                    'processed_at')
    list_filter = ('status', 'method')
    search_fields = ('user__username', 'user__email', 'reference', 'destination')
    readonly_fields = ('account', 'user', 'amount', 'requested_at', 'processed_at',
                       'processed_by')
    actions = (_mark_paid, _reject)


@admin.register(MatchPot)
class MatchPotAdmin(admin.ModelAdmin):
    list_display = ('match', 'collected', 'venue_amount', 'platform_fee', 'surplus',
                    'status', 'created_at')
    list_filter = ('status',)
    search_fields = ('match__title',)


@admin.register(MatchWithdrawal)
class MatchWithdrawalAdmin(admin.ModelAdmin):
    list_display = ('user', 'match', 'share_amount', 'status', 'replacement_user',
                    'created_at')
    list_filter = ('status',)
    search_fields = ('user__username', 'match__title', 'replacement_user__username')


@admin.register(PlayerCreditAccount)
class PlayerCreditAccountAdmin(admin.ModelAdmin):
    list_display = ('user', 'balance', 'updated_at')
    search_fields = ('user__username', 'user__email')


@admin.register(PlayerCreditEntry)
class PlayerCreditEntryAdmin(admin.ModelAdmin):
    list_display = ('account', 'kind', 'amount', 'match', 'created_at')
    list_filter = ('kind',)
    search_fields = ('account__user__username', 'note')
    readonly_fields = ('account', 'amount', 'kind', 'match', 'note', 'created_at')
