"""Venue reservations created when a match host pays their share."""
from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from .models import VenueBooking
from .monetization import BOOKING_SLOT_HOURS, money
from .push import notify

BLOCKING_STATUSES = ('pending', 'reserved', 'confirmed')


def slot_window(match):
    local_dt = timezone.localtime(match.date_time)
    end_dt = local_dt + timedelta(hours=BOOKING_SLOT_HOURS)
    return local_dt, end_dt


def has_conflict(venue, date, start_time, end_time, exclude_id=None):
    qs = VenueBooking.objects.filter(
        venue=venue, date=date, status__in=BLOCKING_STATUSES)
    if exclude_id:
        qs = qs.exclude(id=exclude_id)
    for booking in qs:
        if start_time < booking.end_time and end_time > booking.start_time:
            return True
    return False


@transaction.atomic
def reserve_for_match(match):
    """Hold the venue slot for a match. Idempotent."""
    if match.venue is None or match.booking_status == 'confirmed':
        return VenueBooking.objects.filter(match=match, status='confirmed').first()

    existing = VenueBooking.objects.filter(match=match).order_by('-created_at').first()
    if existing and existing.status in ('reserved', 'confirmed'):
        return existing

    local_dt, end_dt = slot_window(match)
    start_time = local_dt.time().replace(second=0, microsecond=0)
    end_time = end_dt.time().replace(second=0, microsecond=0)
    if has_conflict(
        match.venue, local_dt.date(), start_time, end_time,
        exclude_id=existing.id if existing else None,
    ):
        raise ValueError('That venue slot is already reserved. Pick another time.')

    if existing is None:
        existing = VenueBooking(
            match=match,
            venue=match.venue,
            booked_by=match.organizer,
            date=local_dt.date(),
            start_time=start_time,
            end_time=end_time,
            hours=BOOKING_SLOT_HOURS,
            total_price=money(match.venue.slot_price),
        )
    existing.status = 'reserved'
    existing.payment_status = 'unpaid'
    existing.total_price = money(match.venue.slot_price)
    existing.notes = 'Reserved by a match waiting for the pot'
    existing.save()

    notify(
        match.venue.owner, 'general', 'Venue slot reserved',
        f'{match.title} reserved {match.venue.name} on {local_dt:%a %d %b, %H:%M}. '
        'The booking is confirmed once the player pot covers the field.',
    )
    return existing


@transaction.atomic
def release_reservation(match):
    booking = VenueBooking.objects.filter(match=match, status='reserved').first()
    if booking:
        booking.status = 'cancelled'
        booking.save(update_fields=['status'])
    return booking
