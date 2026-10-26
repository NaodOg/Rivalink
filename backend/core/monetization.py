"""Monetization configuration + helpers.

All rates/fees live here so pricing can be tuned in one place. Amounts are in
ETB. Every fee the platform earns is written to the `PlatformTransaction`
ledger via `record_transaction()`.
"""
from decimal import Decimal, ROUND_HALF_UP

from .models import PlatformTransaction

# ── Pricing ──────────────────────────────────────────────────────────────
PREMIUM_PRICE_ETB = Decimal('100.00')      # Premium subscription, per month
VENUE_COMMISSION_RATE = Decimal('0.10')    # 10% of a venue booking total
HOST_FEE_ETB = Decimal('20.00')            # per hosted match (free tier only)
REFEREE_COMMISSION_RATE = Decimal('0.10')  # 10% of a referee booking fee
TOURNAMENT_FEE_RATE = Decimal('0.12')      # 12% of a tournament entry fee
LEAGUE_FEE_RATE = Decimal('0.12')          # 12% of a league entry fee

# Venues are booked in fixed 2-hour slots (nobody books a single hour).
BOOKING_SLOT_HOURS = 2

# ── Match escrow & cancellation policy ───────────────────────────────────
MATCH_AUTO_CANCEL_HOURS = 6           # check the minimum this long before kickoff
CANCEL_FULL_REFUND_HOURS = 24         # leaving >= this early -> full refund
CANCEL_PARTIAL_REFUND_HOURS = 6       # leaving >= this early -> partial refund
CANCEL_PARTIAL_REFUND_PERCENT = 50    # percent refunded in the partial window
RESULT_AUTO_CONFIRM_HOURS = 48        # auto-confirm an undisputed result after this
DEFAULT_VENUE_CANCEL_HOURS = 24       # default venue cancellation window
HOST_CANCEL_STRIKE_LIMIT = 3          # late host cancellations before suspension
HOST_SUSPENSION_DAYS = 30             # how long a suspended host must wait

TWO_PLACES = Decimal('0.01')


def money(amount) -> Decimal:
    """Coerce to a 2-decimal ETB amount."""
    return Decimal(str(amount)).quantize(TWO_PLACES, rounding=ROUND_HALF_UP)


def venue_commission(total_price) -> Decimal:
    return money(Decimal(str(total_price)) * VENUE_COMMISSION_RATE)


def referee_commission(fee) -> Decimal:
    return money(Decimal(str(fee)) * REFEREE_COMMISSION_RATE)


def tournament_fee(entry_fee) -> Decimal:
    return money(Decimal(str(entry_fee)) * TOURNAMENT_FEE_RATE)


def league_fee(entry_fee) -> Decimal:
    return money(Decimal(str(entry_fee)) * LEAGUE_FEE_RATE)


def host_fee_for(user) -> Decimal:
    """Host fee applies to free users only; Premium hosts pay nothing."""
    from .entitlements import is_premium
    return Decimal('0.00') if is_premium(user) else HOST_FEE_ETB


def record_transaction(kind, amount, payer=None, reference_type='', reference_id=None,
                       status='pending', note=''):
    """Write a revenue row. Returns None for zero/negative amounts."""
    amount = money(amount)
    if amount <= 0:
        return None
    return PlatformTransaction.objects.create(
        kind=kind,
        amount=amount,
        payer=payer,
        reference_type=reference_type,
        reference_id=reference_id,
        status=status,
        note=note[:300],
    )
