import 'package:flutter/material.dart';

import '../../core/data/models/match.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/sport_utils.dart';
import 'pf_badge.dart';
import 'pf_card.dart';

class ExploreFeaturedMatchCard extends StatelessWidget {
  final RivalinkMatch match;
  final VoidCallback? onTap;

  const ExploreFeaturedMatchCard({
    super.key,
    required this.match,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = PFSport.color(match.sport);
    final spots = match.spotsLeft;
    final starts = match.dateTime.difference(DateTime.now());
    final label = starts.inHours < 8 && starts.inMinutes > 0
        ? 'STARTS SOON'
        : 'NEXT UP';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PFRadius.xl),
        child: Container(
          height: 190,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PFRadius.xl),
            border: Border.all(color: color.withValues(alpha: 0.45)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.42),
                PFColors.surfaceRaised,
                PFColors.surface,
              ],
              stops: const [0, 0.58, 1],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: -28,
                bottom: -34,
                child: Icon(
                  sportIcon(match.sport),
                  size: 170,
                  color: Colors.white.withValues(alpha: 0.09),
                ),
              ),
              Positioned(
                right: 14,
                top: 36,
                child: Icon(
                  Icons.sports_soccer_rounded,
                  size: 74,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(PFSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PFBadge(label: label, color: color, solid: true),
                        const SizedBox(width: 8),
                        PFBadge(
                          label: match.sport.toUpperCase(),
                          color: Colors.white,
                        ),
                        const Spacer(),
                        if (spots > 0)
                          PFBadge(
                            label: '$spots LEFT',
                            color: spots <= 3
                                ? PFColors.warning
                                : PFColors.success,
                          )
                        else
                          const PFBadge(
                              label: 'WAITLIST', color: PFColors.danger),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      match.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontSize: 24, height: 1.05),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 13, color: Colors.white70),
                        const SizedBox(width: 5),
                        Text(prettyDate(match.dateTime),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12.5)),
                        const SizedBox(width: 10),
                        const Icon(Icons.place_outlined,
                            size: 13, color: Colors.white70),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            match.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _AvatarStack(
                          names: match.participantsPreview,
                          count: match.currentPlayers,
                          color: color,
                        ),
                        const Spacer(),
                        Text(
                          match.price == 0
                              ? 'Free'
                              : 'Br ${match.price.toStringAsFixed(0)}',
                          style: PFType.number.copyWith(
                            fontSize: 18,
                            color: match.price == 0
                                ? PFColors.success
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.arrow_forward_rounded,
                              size: 18, color: PFColors.background),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExploreMatchCard extends StatelessWidget {
  final RivalinkMatch match;
  final VoidCallback? onTap;

  const ExploreMatchCard({
    super.key,
    required this.match,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = PFSport.color(match.sport);
    final full = match.currentPlayers >= match.maxPlayers;
    final fill = match.maxPlayers == 0
        ? 0.0
        : (match.currentPlayers / match.maxPlayers).clamp(0.0, 1.0);
    final today = _isToday(match.dateTime);

    return PFCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -10,
            bottom: -18,
            child: Icon(
              sportIcon(match.sport),
              size: 96,
              color: color.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateTicket(
                  date: match.dateTime,
                  color: color,
                  today: today,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              match.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            match.price == 0
                                ? 'Free'
                                : 'Br ${match.price.toStringAsFixed(0)}',
                            style: PFType.number.copyWith(
                              fontSize: 14,
                              color: match.price == 0
                                  ? PFColors.success
                                  : color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded,
                              size: 12, color: color),
                          const SizedBox(width: 4),
                          Text(
                            _timeLabel(match.dateTime),
                            style: TextStyle(
                              color: color,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.place_outlined,
                              size: 12, color: PFColors.textTertiary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              match.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: PFColors.textSecondary,
                                  fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          _AvatarStack(
                            names: match.participantsPreview,
                            count: match.currentPlayers,
                            color: color,
                          ),
                          const Spacer(),
                          _SpotBadge(
                            full: full,
                            spots: match.spotsLeft,
                            color: color,
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(PFRadius.pill),
                        child: LinearProgressIndicator(
                          value: fill,
                          minHeight: 4,
                          backgroundColor: PFColors.surfaceHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            full ? PFColors.warning : color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
  }

  static String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    final today = _isToday(dt);
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final time =
        '$hour:${dt.minute.toString().padLeft(2, '0')} $period';
    if (today) return 'Today · $time';
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    if (dt.year == tomorrow.year &&
        dt.month == tomorrow.month &&
        dt.day == tomorrow.day) {
      return 'Tomorrow · $time';
    }
    return '${days[dt.weekday - 1]} · $time';
  }
}

class _DateTicket extends StatelessWidget {
  final DateTime date;
  final Color color;
  final bool today;

  const _DateTicket({
    required this.date,
    required this.color,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return Container(
      width: 54,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PFRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.38)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${date.day}',
            style: PFType.number.copyWith(
              fontSize: 22,
              color: PFColors.text,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            months[date.month - 1],
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            today ? 'TODAY' : weekdays[date.weekday - 1],
            style: const TextStyle(
              color: PFColors.textTertiary,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotBadge extends StatelessWidget {
  final bool full;
  final int spots;
  final Color color;

  const _SpotBadge({
    required this.full,
    required this.spots,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final label = full
        ? 'WAITLIST'
        : (spots <= 3 ? '$spots LEFT' : '$spots OPEN');
    final tint = full
        ? PFColors.danger
        : (spots <= 3 ? PFColors.warning : color);
    return PFBadge(label: label, color: tint);
  }
}

class _AvatarStack extends StatelessWidget {
  final List<String> names;
  final int count;
  final Color color;

  const _AvatarStack({
    required this.names,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final shown = names.take(3).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++)
          Align(
            widthFactor: 0.7,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(color: PFColors.surface, width: 1.5),
              ),
              child: Text(
                shown[i].trim().isEmpty
                    ? '?'
                    : shown[i].trim()[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
        const SizedBox(width: 5),
        Text(
          '$count going',
          style: const TextStyle(
              color: PFColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
