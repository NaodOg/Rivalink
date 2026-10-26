"""Product analytics: event ingestion helpers + the actionable report.

Two entry points:
    track(user, name, props)            -> server-side event (authoritative)
    build_report(days=30)               -> dict consumed by the API + report command

The report is intentionally opinionated: it returns raw metrics *and* a list of
plain-English insights/recommendations so it can be used to decide what to fix
or to brief an advertiser.
"""
from collections import defaultdict
from datetime import timedelta

from django.contrib.auth.models import User
from django.db.models import Count, Sum
from django.utils import timezone

from .models import (
    AnalyticsEvent, Match, MatchParticipant, MatchResult, Payment, PlatformTransaction,
    Tournament, TournamentTeam, UserProfile, VenueBooking,
)

# ── Ingestion ─────────────────────────────────────────────────────────────

def track(user, name, properties=None, session_id='', platform='server'):
    """Record one server-side event. Never raises."""
    try:
        AnalyticsEvent.objects.create(
            user=user if getattr(user, 'is_authenticated', False) else None,
            name=name[:80],
            properties=properties or {},
            session_id=session_id[:64],
            platform=platform,
        )
    except Exception:  # analytics must never break a request
        pass


# ── Report helpers ────────────────────────────────────────────────────────

def _funnel(rows, steps):
    """Count users who completed each step in order (within the window)."""
    by_user = defaultdict(lambda: defaultdict(list))
    for uid, name, ts in rows:
        if uid and name in steps:
            by_user[uid][name].append(ts)

    counts = [0] * len(steps)
    converted = 0
    for events in by_user.values():
        t = None
        ok = True
        for i, step in enumerate(steps):
            times = events.get(step)
            if not times:
                ok = False
                break
            if t is None:
                t = min(times)
            else:
                later = [x for x in times if x >= t]
                if not later:
                    ok = False
                    break
                t = min(later)
            counts[i] += 1
        if ok:
            converted += 1

    base = counts[0] if counts else 0
    return {
        'steps': [
            {
                'name': step,
                'users': counts[i],
                'pct_of_start': round(counts[i] / base * 100, 1) if base else 0,
            }
            for i, step in enumerate(steps)
        ],
        'conversion': round(converted / base * 100, 1) if base else 0,
    }


def _retention(rows, window_start):
    """Weekly cohorts: % of each cohort active on day 1, 7 and 30."""
    first_seen = {}
    activity = defaultdict(set)
    for uid, _name, ts in rows:
        if not uid:
            continue
        day = ts.date()
        activity[uid].add(day)
        if uid not in first_seen or day < first_seen[uid]:
            first_seen[uid] = day

    cohorts = defaultdict(list)
    for uid, day in first_seen.items():
        iso = day.isocalendar()
        cohorts[f'{iso[0]}-W{iso[1]:02d}'].append(uid)

    out = []
    for key in sorted(cohorts.keys())[-8:]:
        users = cohorts[key]
        size = len(users)
        if not size:
            continue

        def pct(offset):
            if offset == 0:
                return 100.0
            hit = sum(
                1 for uid in users
                if (first_seen[uid] + timedelta(days=offset)) in activity[uid]
            )
            return round(hit / size * 100, 1)

        out.append({
            'cohort': key,
            'users': size,
            'd1': pct(1),
            'd7': pct(7),
            'd30': pct(30),
        })
    return out


def _pct(part, total):
    return round(part / total * 100, 1) if total else 0.0


# ── Report ────────────────────────────────────────────────────────────────

def build_report(days=30):
    end = timezone.now()
    start = end - timedelta(days=days)

    events = list(
        AnalyticsEvent.objects.filter(created_at__gte=start)
        .values('user_id', 'name', 'created_at', 'session_id', 'platform', 'properties')
        .order_by('created_at')
    )
    rows = [(e['user_id'], e['name'], e['created_at']) for e in events]

    # ── Audience ──
    total_users = User.objects.filter(is_active=True).count()
    new_users = User.objects.filter(date_joined__gte=start).count()
    active_ids = {e['user_id'] for e in events if e['user_id']}
    active_users = len(active_ids)

    day_counts = defaultdict(set)
    for e in events:
        if e['user_id']:
            day_counts[e['created_at'].date()].add(e['user_id'])
    dau_series = [
        {'date': d.isoformat(), 'users': len(uids)}
        for d, uids in sorted(day_counts.items())
    ]
    mau_cutoff = end - timedelta(days=30)
    mau_ids = {
        e['user_id'] for e in events
        if e['user_id'] and e['created_at'] >= mau_cutoff
    }
    wau_cutoff = end - timedelta(days=7)
    wau_ids = {
        e['user_id'] for e in events
        if e['user_id'] and e['created_at'] >= wau_cutoff
    }
    mau = len(mau_ids)
    dau_today = len(day_counts.get(end.date(), set()))
    stickiness = _pct(dau_today, mau)

    # ── Sessions (client events) ──
    sessions = defaultdict(list)
    for e in events:
        if e['session_id']:
            sessions[e['session_id']].append(e['created_at'])
    durations = [
        (max(times) - min(times)).total_seconds()
        for times in sessions.values() if len(times) > 1
    ]
    session_count = len(sessions)
    avg_duration = round(sum(durations) / len(durations), 1) if durations else 0
    events_per_session = round(len(events) / session_count, 1) if session_count else 0
    sessions_per_user = round(session_count / active_users, 2) if active_users else 0

    # ── Screens ──
    screen_views = defaultdict(int)
    screen_users = defaultdict(set)
    exit_ms = defaultdict(list)
    for e in events:
        props = e['properties'] or {}
        screen = props.get('screen')
        if not screen:
            continue
        if e['name'] == 'screen_viewed':
            screen_views[screen] += 1
            if e['user_id']:
                screen_users[screen].add(e['user_id'])
        elif e['name'] == 'screen_exited':
            try:
                exit_ms[screen].append(float(props.get('duration_ms', 0)))
            except (TypeError, ValueError):
                pass

    total_screen_views = sum(screen_views.values()) or 1
    screens = [
        {
            'screen': screen,
            'views': views,
            'users': len(screen_users[screen]),
            'share_pct': _pct(views, total_screen_views),
            'avg_seconds': round(
                sum(exit_ms[screen]) / len(exit_ms[screen]) / 1000, 1
            ) if exit_ms[screen] else None,
        }
        for screen, views in sorted(screen_views.items(), key=lambda kv: -kv[1])
    ]

    # ── Funnels ──
    funnels = {
        'match': _funnel(rows, ['match_viewed', 'match_join_clicked', 'match_joined']),
        'venue': _funnel(rows, ['venue_viewed', 'booking_sheet_opened', 'booking_created']),
        'league': _funnel(rows, ['league_viewed', 'league_joined']),
        'premium': _funnel(rows, ['premium_viewed', 'premium_purchased']),
    }
    # Activation: signup -> any first real action (join/host/book/league).
    action_events = {'match_joined', 'match_created', 'booking_created', 'league_joined'}
    activation_rows = []
    for uid, name, ts in rows:
        if name == 'signup_completed':
            activation_rows.append((uid, name, ts))
        elif name in action_events:
            activation_rows.append((uid, 'first_action', ts))
    funnels['activation'] = _funnel(activation_rows, ['signup_completed', 'first_action'])

    # ── Retention ──
    retention = _retention(rows, start)

    # ── Feature adoption ──
    features = {
        'match_viewed': 'Viewed a match',
        'match_joined': 'Joined a match',
        'match_created': 'Hosted a match',
        'booking_created': 'Booked a venue',
        'league_viewed': 'Viewed a league',
        'league_joined': 'Joined a league',
        'premium_viewed': 'Saw premium',
        'search_used': 'Searched',
    }
    feature_users = defaultdict(set)
    for e in events:
        if e['user_id'] and e['name'] in features:
            feature_users[e['name']].add(e['user_id'])
    feature_adoption = [
        {
            'event': name,
            'label': label,
            'users': len(feature_users[name]),
            'pct_of_active': _pct(len(feature_users[name]), active_users),
        }
        for name, label in features.items()
    ]
    feature_adoption.sort(key=lambda f: -f['users'])

    # ── Segments ──
    profiles = {
        p.user_id: p for p in UserProfile.objects.filter(user_id__in=active_ids)
    }
    by_city = defaultdict(int)
    for uid in active_ids:
        profile = profiles.get(uid)
        city = (profile.location.strip() if profile else '') or 'Unknown'
        by_city[city.split(',')[0].strip()] += 1
    city_rows = [
        {'city': city, 'users': n}
        for city, n in sorted(by_city.items(), key=lambda kv: -kv[1])[:10]
    ]

    sport_views = defaultdict(int)
    search_terms = defaultdict(int)
    error_count = 0
    top_errors = defaultdict(int)
    platform_counts = defaultdict(int)
    for e in events:
        props = e['properties'] or {}
        if props.get('sport'):
            sport_views[str(props['sport'])] += 1
        if e['name'] == 'search_used' and props.get('q'):
            search_terms[str(props['q']).lower()[:40]] += 1
        if e['name'] == 'error_shown':
            error_count += 1
            top_errors[str(props.get('error') or props.get('screen') or 'unknown')[:60]] += 1
        platform_counts[e['platform']] += 1
    sport_rows = [
        {'sport': s, 'events': n}
        for s, n in sorted(sport_views.items(), key=lambda kv: -kv[1])[:8]
    ]
    search_rows = [
        {'query': q, 'count': n}
        for q, n in sorted(search_terms.items(), key=lambda kv: -kv[1])[:10]
    ]
    platform_rows = [
        {'platform': p, 'events': n}
        for p, n in sorted(platform_counts.items(), key=lambda kv: -kv[1])
    ]

    # ── Business metrics (matches, bookings, premium, refunds, revenue) ──
    business = _business_metrics(start, end, active_users, total_users)

    # ── Insights ──
    insights = _insights(
        days=days,
        active_users=active_users,
        new_users=new_users,
        total_users=total_users,
        mau=mau,
        stickiness=stickiness,
        funnels=funnels,
        retention=retention,
        screens=screens,
        feature_adoption=feature_adoption,
        session_count=session_count,
        avg_duration=avg_duration,
        error_count=error_count,
        business=business,
    )

    return {
        'generated_at': end.isoformat(),
        'period_days': days,
        'users': {
            'total': total_users,
            'new': new_users,
            'active': active_users,
            'dau': dau_today,
            'wau': len(wau_ids),
            'mau': mau,
            'stickiness_pct': stickiness,
            'dau_series': dau_series,
        },
        'sessions': {
            'count': session_count,
            'avg_duration_sec': avg_duration,
            'events_per_session': events_per_session,
            'sessions_per_active_user': sessions_per_user,
        },
        'screens': screens,
        'funnels': funnels,
        'retention': retention,
        'feature_adoption': feature_adoption,
        'segments': {
            'by_city': city_rows,
            'by_sport': sport_rows,
            'by_platform': platform_rows,
            'top_searches': search_rows,
        },
        'quality': {
            'error_events': error_count,
            'top_errors': [
                {'error': e, 'count': n}
                for e, n in sorted(top_errors.items(), key=lambda kv: -kv[1])[:5]
            ],
        },
        'business': business,
        'revenue': business['revenue'],
        'insights': insights,
    }


def _business_metrics(start, end, active_users, total_users):
    """Operational + money metrics used by the operating plan and ads media kit."""
    from datetime import date, timedelta

    from django.db.models import Avg, Q

    matches_created = Match.objects.filter(created_at__gte=start)
    results_confirmed = MatchResult.objects.filter(status='confirmed', confirmed_at__gte=start)
    cancelled = Match.objects.filter(cancelled_at__gte=start)
    active_matches = Match.objects.filter(is_active=True, date_time__gte=end - timedelta(hours=6))

    fill = list(matches_created.values_list('current_players', 'max_players'))
    fill_rate = round(sum(c for c, _ in fill) / sum(m or 1 for _, m in fill) * 100, 1) if fill else 0.0
    avg_players = round(sum(c for c, _ in fill) / len(fill), 1) if fill else 0.0
    completed_rate = round(results_confirmed.count() / matches_created.count() * 100, 1) if matches_created.count() else 0.0

    by_sport = [
        {'sport': row['sport'], 'matches': row['n']}
        for row in matches_created.values('sport').annotate(n=Count('id')).order_by('-n')[:8]
    ]

    daily = defaultdict(lambda: {'date': None, 'matches': 0, 'bookings': 0, 'revenue': '0'})
    for m in matches_created.only('created_at'):
        key = m.created_at.date().isoformat()
        daily[key]['date'] = key
        daily[key]['matches'] += 1

    bookings = VenueBooking.objects.filter(created_at__gte=start)
    for b in bookings.only('created_at'):
        key = b.created_at.date().isoformat()
        daily[key]['date'] = key
        daily[key]['bookings'] += 1

    revenue_rows = list(
        PlatformTransaction.objects.filter(created_at__gte=start)
        .exclude(kind='match_share')
        .values('kind', 'status')
        .annotate(total=Sum('amount'), count=Count('id'))
    )

    def sum_status(status):
        return sum(r['total'] or 0 for r in revenue_rows if r['status'] == status)

    collected = sum_status('collected')
    pending = sum_status('pending')
    ledger_refunded = sum_status('refunded')
    net = collected - ledger_refunded

    by_kind = {}
    for row in revenue_rows:
        if row['status'] != 'collected':
            continue
        entry = by_kind.setdefault(row['kind'], {'kind': row['kind'], 'total': 0, 'count': 0})
        entry['total'] += row['total'] or 0
        entry['count'] += row['count']

    revenue_daily = {k: v for k, v in daily.items()}
    for r in PlatformTransaction.objects.filter(
            created_at__gte=start, status='collected').exclude(
            kind='match_share').only('created_at', 'amount'):
        key = r.created_at.date().isoformat()
        revenue_daily[key]['date'] = key
        current = float(revenue_daily[key]['revenue'] or 0)
        revenue_daily[key]['revenue'] = str(round(current + float(r.amount), 2))

    bookings_confirmed = bookings.filter(status__in=['confirmed', 'completed']).count()
    bookings_cancelled = bookings.filter(status='cancelled').count()
    bookings_paid = bookings.filter(payment_status='paid').count()
    bookings_refunded = bookings.filter(payment_status='refunded')
    booking_refund_amount = bookings_refunded.aggregate(s=Sum('total_price'))['s'] or 0
    cancellation_rate = round(bookings_cancelled / bookings.count() * 100, 1) if bookings.count() else 0.0
    refund_rate = round(bookings_refunded.count() / bookings.count() * 100, 1) if bookings.count() else 0.0

    premium_profiles = UserProfile.objects.filter(is_premium=True).filter(
        Q(premium_expires__isnull=True) | Q(premium_expires__gt=end))
    premium_active = premium_profiles.count()
    premium_expiring = UserProfile.objects.filter(
        is_premium=True, premium_expires__gt=end,
        premium_expires__lte=end + timedelta(days=7)).count()
    premium_purchases = PlatformTransaction.objects.filter(
        kind='premium', status='collected', created_at__gte=start).count()
    premium_conversion = round(premium_active / active_users * 100, 1) if active_users else 0.0

    payments_qs = Payment.objects.filter(created_at__gte=start)
    refunded_payments = payments_qs.filter(status='refunded')
    payment_refund_amount = refunded_payments.aggregate(s=Sum('amount'))['s'] or 0
    refunded_participants = MatchParticipant.objects.filter(
        payment_status__in=['refunded', 'partially_refunded']).count()

    tournaments_created = Tournament.objects.filter(created_at__gte=start).count()
    tournament_teams = TournamentTeam.objects.filter(joined_at__gte=start).count()

    paying_users = len({r['payer_id'] for r in PlatformTransaction.objects.filter(
        created_at__gte=start, status='collected', payer__isnull=False).values('payer_id')})

    revenue = {
        'gross': str(collected),
        'pending': str(pending),
        'refunded': str(ledger_refunded),
        'net': str(net),
        'total': str(net),
        'by_kind': sorted(by_kind.values(), key=lambda r: -r['total']),
        'arpu': str(round(net / active_users, 2)) if active_users else '0',
        'arppu': str(round(net / paying_users, 2)) if paying_users else '0',
        'paying_users': paying_users,
    }

    return {
        'matches': {
            'created': matches_created.count(),
            'completed': results_confirmed.count(),
            'completion_rate_pct': completed_rate,
            'cancelled': cancelled.count(),
            'active_now': active_matches.count(),
            'fill_rate_pct': fill_rate,
            'avg_players': avg_players,
            'by_sport': by_sport,
        },
        'bookings': {
            'created': bookings.count(),
            'confirmed': bookings_confirmed,
            'cancelled': bookings_cancelled,
            'paid': bookings_paid,
            'refunded': bookings_refunded.count(),
            'refund_amount': str(booking_refund_amount),
            'cancellation_rate_pct': cancellation_rate,
            'refund_rate_pct': refund_rate,
        },
        'premium': {
            'active': premium_active,
            'expiring_7d': premium_expiring,
            'new_purchases': premium_purchases,
            'conversion_pct': premium_conversion,
        },
        'refunds': {
            'ledger_count': sum(r['count'] for r in revenue_rows if r['status'] == 'refunded'),
            'ledger_amount': str(ledger_refunded),
            'payments_count': refunded_payments.count(),
            'payments_amount': str(payment_refund_amount),
            'participants_refunded': refunded_participants,
        },
        'tournaments': {
            'created': tournaments_created,
            'team_registrations': tournament_teams,
        },
        'revenue': revenue,
        'daily': [v for _, v in sorted(revenue_daily.items())][-30:],
    }


def _insights(**m):
    """Turn the numbers into plain-English, actionable observations."""
    out = []

    # Stickiness
    if m['mau']:
        if m['stickiness'] >= 20:
            out.append(
                f'Stickiness is strong: {m["stickiness"]}% of monthly users are active today '
                f'(above 20% is healthy for a community app).'
            )
        else:
            out.append(
                f'Only {m["stickiness"]}% of monthly users came back today (DAU/MAU). '
                'Increase re-engagement with reminders for upcoming matches and league fixtures.'
            )

    # Activation
    activation = m['funnels']['activation']
    if activation['steps'][0]['users']:
        if activation['conversion'] < 40:
            out.append(
                f'Activation is weak: only {activation["conversion"]}% of new signups join or book '
                'something. Add a guided first action on Home (e.g. "Join a match near you") and '
                'prompt profile completion right after signup.'
            )
        else:
            out.append(
                f'Activation is healthy at {activation["conversion"]}% of signups completing a '
                'first action within the period.'
            )

    # Retention
    if m['retention']:
        recent = m['retention'][-1]
        if recent['d7'] < 25:
            out.append(
                f'Week-1 retention is {recent["d7"]}% for the latest cohort. '
                'Users who join a match in their first week return far more — push a first-match '
                'CTA and send a day-2 reminder.'
            )
        else:
            out.append(
                f'Week-1 retention is {recent["d7"]}% for the latest cohort — keep doing what '
                'works and focus on week-4 (D30 is '
                f'{recent["d30"]}%).'
            )

    # Screen time
    if m['screens']:
        top = m['screens'][0]
        out.append(
            f'{top["screen"]} gets the most attention ({top["share_pct"]}% of screen views). '
            'Put your highest-value actions and promos on that screen.'
        )
        slow = [s for s in m['screens'] if s['avg_seconds'] and s['avg_seconds'] < 8]
        if slow:
            names = ', '.join(s['screen'] for s in slow[:3])
            out.append(
                f'Users leave {names} in under 8s on average - these screens may look empty, '
                'confusing, or lack an obvious next step.'
            )

    # Funnels
    match = m['funnels']['match']
    if match['steps'][0]['users']:
        out.append(
            f'Match funnel: {match["steps"][0]["users"]} views -> '
            f'{match["steps"][1]["users"]} join taps ({match["steps"][1]["pct_of_start"]}%) -> '
            f'{match["steps"][2]["users"]} joins ({match["steps"][2]["pct_of_start"]}%).'
            + (' The tap-to-join drop means the join flow or premium paywall is costing you '
               'signups.' if match['steps'][1]['users'] and
               match['steps'][2]['users'] < match['steps'][1]['users'] * 0.7 else '')
        )
    venue = m['funnels']['venue']
    if venue['steps'][1]['users']:
        out.append(
            f'Venue funnel: {venue["steps"][1]["users"]} opened the booking sheet but only '
            f'{venue["steps"][2]["users"]} completed a booking '
            f'({venue["steps"][2]["pct_of_start"]}% of views).'
        )
    premium = m['funnels']['premium']
    if premium['steps'][0]['users']:
        out.append(
            f'Premium: {premium["steps"][0]["users"]} people saw the paywall and '
            f'{premium["steps"][1]["users"]} purchased ({premium["conversion"]}%).'
        )

    # Engagement
    if m['avg_duration']:
        out.append(
            f'Average session length is {m["avg_duration"]}s across '
            f'{m["session_count"]} sessions.'
        )

    # Quality
    if m['error_count']:
        out.append(
            f'{m["error_count"]} error events were shown to users this period — fix the top '
            'one before spending on ads.'
        )

    # Business health
    b = m.get('business') or {}
    matches = b.get('matches') or {}
    if matches.get('created'):
        out.append(
            f'{matches["created"]} matches were created and {matches["completed"]} completed '
            f'({matches["completion_rate_pct"]}%); average fill is {matches["fill_rate_pct"]}% '
            f'({matches["avg_players"]} players per match).'
            + (' Low fill means the match list needs clearer urgency and better opponent '
               'matching.' if matches['fill_rate_pct'] < 60 else '')
        )
    bookings = b.get('bookings') or {}
    if bookings.get('created'):
        out.append(
            f'{bookings["created"]} venue bookings were made: {bookings["confirmed"]} confirmed, '
            f'{bookings["cancelled"]} cancelled ({bookings["cancellation_rate_pct"]}%), '
            f'{bookings["refunded"]} refunded ({bookings["refund_rate_pct"]}%). '
            'A cancellation rate above 20% signals unreliable matches or unclear policies.'
        )
    premium = b.get('premium') or {}
    out.append(
        f'Pro users: {premium.get("active", 0)} active '
        f'({premium.get("conversion_pct", 0)}% of active users); '
        f'{premium.get("new_purchases", 0)} purchases this period; '
        f'{premium.get("expiring_7d", 0)} expire within 7 days — send renewal reminders.'
    )
    revenue = b.get('revenue') or {}
    if (revenue.get('by_kind') or None):
        top = revenue['by_kind'][0]
        out.append(
            f'Revenue: gross Br {revenue["gross"]}, refunds Br {revenue["refunded"]}, '
            f'net Br {revenue["net"]} (ARPU Br {revenue["arpu"]}); '
            f'{top["kind"]} is the largest stream (Br {top["total"]}).'
        )
    elif float(revenue.get('pending') or 0) > 0:
        out.append(
            f'No collected revenue yet, but Br {revenue["pending"]} is pending collection. '
            'Close the loop: confirm bookings, release escrow, and settle commissions.'
        )
    else:
        out.append(
            'No platform revenue recorded in this period. If you plan to run ads, '
            'turn on venue commissions and premium before spending.'
        )
    refunds = b.get('refunds') or {}
    if refunds.get('payments_count') or refunds.get('ledger_count'):
        out.append(
            f'Refunds this period: {refunds.get("payments_count", 0)} payments '
            f'(Br {refunds.get("payments_amount", "0")}) and '
            f'{refunds.get("participants_refunded", 0)} match participants. '
            'Track refund reasons — they are product feedback.'
        )

    return out
