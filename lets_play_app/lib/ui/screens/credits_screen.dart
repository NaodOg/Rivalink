import 'package:flutter/material.dart';

import '../../core/data/services/analytics_service.dart';
import '../../core/data/services/credit_service.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_scaffold.dart';
import '../widgets/pf_section_header.dart';

class CreditsScreen extends StatefulWidget {
  final String token;
  const CreditsScreen({super.key, required this.token});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  double _balance = 0;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.event('credits_viewed');
    _load();
  }

  Future<void> _load() async {
    final result = await CreditService.getCredits(widget.token);
    if (!mounted) return;
    setState(() {
      if (result['success'] == true) {
        _balance =
            double.tryParse(result['balance']?.toString() ?? '0') ?? 0;
        _entries = ((result['entries'] as List?) ?? const [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _error = false;
      } else {
        _error = true;
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Credits'),
      ),
      padding: EdgeInsets.zero,
      body: RefreshIndicator(
        color: PFColors.primary,
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: PFColors.primary))
            : _error
                ? ListView(
                    children: [
                      PFEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Could not load credit',
                        message: 'Check your connection and try again.',
                        actionLabel: 'Retry',
                        onAction: _load,
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(PFSpacing.xl),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(PFRadius.xl),
                          border: Border.all(color: PFColors.border),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              PFColors.success.withValues(alpha: 0.18),
                              PFColors.surface,
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MATCH CREDIT',
                                style:
                                    Theme.of(context).textTheme.labelSmall),
                            const SizedBox(height: 8),
                            Text(
                              'Br ${_balance.toStringAsFixed(2)}',
                              style: PFType.number.copyWith(
                                fontSize: 38,
                                color: PFColors.success,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Credit is added when a booked match has spare pot money '
                              'after withdrawals. It stays in your account for future bookings.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: PFSpacing.xxl),
                      PFSectionHeader(
                        eyebrow: 'History',
                        title: 'Credit activity',
                        accent: PFColors.success,
                      ),
                      const SizedBox(height: PFSpacing.md),
                      if (_entries.isEmpty)
                        const PFEmptyState(
                          icon: Icons.savings_outlined,
                          title: 'No credit yet',
                          message:
                              'If a booked match has spare money at kickoff, your share will appear here.',
                        )
                      else
                        PFCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          child: Column(
                            children: [
                              for (var i = 0; i < _entries.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                      height: 1, color: PFColors.hairline),
                                _entryTile(_entries[i]),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _entryTile(Map<String, dynamic> entry) {
    final amount =
        double.tryParse(entry['amount']?.toString() ?? '0') ?? 0;
    final positive = amount >= 0;
    final created = DateTime.tryParse(entry['created_at']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (positive ? PFColors.success : PFColors.textSecondary)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(PFRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              positive
                  ? Icons.add_card_rounded
                  : Icons.remove_circle_outline_rounded,
              size: 18,
              color: positive ? PFColors.success : PFColors.textSecondary,
            ),
          ),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['match_title']?.toString() ??
                      (positive ? 'Match credit' : 'Credit used'),
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if ((entry['note']?.toString() ?? '').isNotEmpty)
                      entry['note'],
                    if (created != null) prettyDate(created.toLocal()),
                  ].where((part) => part != null && part.toString().isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: PFSpacing.sm),
          Text(
            '${positive ? '+' : ''}Br ${amount.abs().toStringAsFixed(2)}',
            style: PFType.number.copyWith(
              fontSize: 14,
              color: positive ? PFColors.success : PFColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
