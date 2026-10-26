"""Markdown rendering for the analytics dashboard export."""


def _table(headers, rows):
    lines = ['| ' + ' | '.join(headers) + ' |',
             '|' + '|'.join([' --- '] * len(headers)) + '|']
    for row in rows:
        lines.append('| ' + ' | '.join(str(c) for c in row) + ' |')
    return '\n'.join(lines)


def render_markdown(report):
    u = report['users']
    s = report['sessions']
    lines = [
        '# Rivalink — Product Analytics Report',
        '',
        f"**Period:** last {report['period_days']} days  ",
        f"**Generated:** {report['generated_at']}",
        '',
        '## Executive summary',
        '',
    ]
    for insight in report['insights']:
        lines.append(f'- {insight}')

    lines += [
        '',
        '## Audience (for growth & advertising)',
        '',
        _table(
            ['Metric', 'Value'],
            [
                ['Total users', u['total']],
                ['New users', u['new']],
                ['Active users', u['active']],
                ['DAU', u['dau']],
                ['WAU', u['wau']],
                ['MAU', u['mau']],
                ['Stickiness (DAU/MAU)', f"{u['stickiness_pct']}%"],
                ['Sessions', s['count']],
                ['Avg session length', f"{s['avg_duration_sec']}s"],
                ['Events per session', s['events_per_session']],
            ],
        ),
        '',
        '### Where users are (city)',
        '',
        _table(['City', 'Active users'],
               [[r['city'], r['users']] for r in report['segments']['by_city']] or [['—', '—']]),
        '',
        '### Sport interest (events mentioning a sport)',
        '',
        _table(['Sport', 'Events'],
               [[r['sport'], r['events']] for r in report['segments']['by_sport']] or [['—', '—']]),
        '',
        '### Platform',
        '',
        _table(['Platform', 'Events'],
               [[r['platform'], r['events']] for r in report['segments']['by_platform']] or [['—', '—']]),
        '',
        '## Engagement',
        '',
        _table(['Screen', 'Views', 'Users', 'Share', 'Avg time'],
               [[r['screen'], r['views'], r['users'], f"{r['share_pct']}%",
                 f"{r['avg_seconds']}s" if r['avg_seconds'] else '—']
                for r in report['screens']] or [['—', '—', '—', '—', '—']]),
        '',
        '## Funnels',
        '',
    ]
    for name, funnel in report['funnels'].items():
        steps = ' > '.join(
            f"{step['name']} ({step['users']}, {step['pct_of_start']}%)"
            for step in funnel['steps']
        )
        lines.append(f"- **{name.title()}**: {steps} — end-to-end: {funnel['conversion']}%")

    lines += [
        '',
        '## Retention (weekly cohorts)',
        '',
        _table(['Cohort', 'Users', 'D1', 'D7', 'D30'],
               [[r['cohort'], r['users'], f"{r['d1']}%", f"{r['d7']}%", f"{r['d30']}%"]
                for r in report['retention']] or [['—', '—', '—', '—', '—']]),
        '',
        '## Feature adoption',
        '',
        _table(['Feature', 'Users', '% of active'],
               [[r['label'], r['users'], f"{r['pct_of_active']}%"]
                for r in report['feature_adoption']] or [['—', '—', '—']]),
        '',
        '## Search demand',
        '',
        _table(['Query', 'Count'],
               [[r['query'], r['count']] for r in report['segments']['top_searches']] or [['—', '—']]),
        '',
        '## Quality',
        '',
        _table(['Error', 'Count'],
               [[r['error'], r['count']] for r in report['quality']['top_errors']] or [['none', '0']]),
        '',
        '## Business health',
        '',
        '### Matches',
        '',
        _table(
            ['Metric', 'Value'],
            [
                ['Created', report['business']['matches']['created']],
                ['Completed (confirmed results)', report['business']['matches']['completed']],
                ['Completion rate', f"{report['business']['matches']['completion_rate_pct']}%"],
                ['Cancelled', report['business']['matches']['cancelled']],
                ['Active now', report['business']['matches']['active_now']],
                ['Average fill', f"{report['business']['matches']['fill_rate_pct']}%"],
                ['Average players per match', report['business']['matches']['avg_players']],
            ],
        ),
        '',
        '### Venue bookings',
        '',
        _table(
            ['Metric', 'Value'],
            [
                ['Created', report['business']['bookings']['created']],
                ['Confirmed', report['business']['bookings']['confirmed']],
                ['Cancelled', report['business']['bookings']['cancelled']],
                ['Cancellation rate', f"{report['business']['bookings']['cancellation_rate_pct']}%"],
                ['Paid', report['business']['bookings']['paid']],
                ['Refunded', report['business']['bookings']['refunded']],
                ['Refund amount', f"Br {report['business']['bookings']['refund_amount']}"],
            ],
        ),
        '',
        '### Premium (Pro users)',
        '',
        _table(
            ['Metric', 'Value'],
            [
                ['Active Pro users', report['business']['premium']['active']],
                ['Pro conversion', f"{report['business']['premium']['conversion_pct']}% of active users"],
                ['New purchases this period', report['business']['premium']['new_purchases']],
                ['Expiring within 7 days', report['business']['premium']['expiring_7d']],
            ],
        ),
        '',
        '### Refunds',
        '',
        _table(
            ['Source', 'Count', 'Amount'],
            [
                ['Payments refunded', report['business']['refunds']['payments_count'],
                 f"Br {report['business']['refunds']['payments_amount']}"],
                ['Ledger refunds', report['business']['refunds']['ledger_count'],
                 f"Br {report['business']['refunds']['ledger_amount']}"],
                ['Match participants refunded',
                 report['business']['refunds']['participants_refunded'], '-'],
            ],
        ),
        '',
        '### Daily activity (last 30 days)',
        '',
        _table(
            ['Date', 'Matches', 'Bookings', 'Revenue'],
            [[d['date'], d['matches'], d['bookings'], f"Br {d['revenue']}"]
             for d in report['business']['daily']] or [['-', '-', '-', '-']],
        ),
        '',
        '## Revenue',
        '',
        f"**Gross collected:** Br {report['revenue']['gross']}  ",
        f"**Refunded:** Br {report['revenue']['refunded']}  ",
        f"**Pending:** Br {report['revenue']['pending']}  ",
        f"**Net:** Br {report['revenue']['net']}  ",
        f"**ARPU:** Br {report['revenue']['arpu']}  ",
        f"**ARPPU:** Br {report['revenue']['arppu']}",
        '',
        _table(['Stream', 'Transactions', 'Amount (collected)'],
               [[r['kind'], r['count'], f"Br {r['total']}"]
                for r in report['revenue']['by_kind']] or [['-', '-', '-']]),
        '',
        '---',
        '',
        '## Recommended actions',
        '',
    ]
    # Actions derived from the same data (ordered by expected impact).
    funnels = report['funnels']
    if funnels['activation']['conversion'] < 40:
        lines.append('1. **Fix activation first** — add a guided "join a match" step after signup.')
    if funnels['match']['steps'][1]['users'] and (
            funnels['match']['steps'][2]['users'] < funnels['match']['steps'][1]['users'] * 0.7):
        lines.append('2. **Reduce join friction** — the tap-to-join drop is large; check the paywall/premium gate.')
    if funnels['venue']['steps'][1]['users'] and (
            funnels['venue']['steps'][2]['users'] < funnels['venue']['steps'][1]['users'] * 0.5):
        lines.append('3. **Improve the booking sheet** — most people who open it do not complete.')
    if report['retention'] and report['retention'][-1]['d7'] < 25:
        lines.append('4. **Retention push** — day-2 reminders and weekly fixtures for new users.')
    slow = [x for x in report['screens'] if x['avg_seconds'] and x['avg_seconds'] < 8]
    if slow:
        lines.append('5. **Polish weak screens** — ' +
                     ', '.join(x['screen'] for x in slow[:3]) + ' are exited in under 8s.')
    if report['quality']['error_events']:
        lines.append('6. **Fix errors before ads** — users are seeing error states this period.')
    if not lines or lines[-1] == '':
        lines.append('1. Keep instrumenting: you need more data for confident recommendations.')
    lines.append('')
    return '\n'.join(lines)
