import 'package:flutter/material.dart';

import '../../core/data/services/analytics_service.dart';
import '../../core/data/services/payment_service.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_scaffold.dart';

class PaymentsScreen extends StatefulWidget {
  final String token;
  const PaymentsScreen({super.key, required this.token});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.event('payments_viewed');
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _payments.isEmpty;
      _error = false;
    });
    final result = await PaymentService.getPaymentHistory(widget.token);
    if (!mounted) return;
    setState(() {
      if (result['success'] == true) {
        _payments = ((result['payments'] as List?) ?? const [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
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
        title: const Text('Payments'),
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
                        title: 'Could not load payments',
                        message: 'Check your connection and try again.',
                        actionLabel: 'Retry',
                        onAction: _load,
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      PFCard(
                        raised: true,
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: PFColors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(PFRadius.sm),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.lock_outline_rounded,
                                  color: PFColors.primary, size: 20),
                            ),
                            const SizedBox(width: PFSpacing.md),
                            Expanded(
                              child: Text(
                                'Checkout is handled by Chapa. '
                                'Rivalink never stores your card details.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: PFSpacing.xl),
                      Text('PAYMENT HISTORY',
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: PFSpacing.sm),
                      if (_payments.isEmpty)
                        const PFEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No payments yet',
                          message:
                              'Premium, venue bookings and match shares will appear here.',
                        )
                      else
                        PFCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          child: Column(
                            children: [
                              for (var i = 0; i < _payments.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                      height: 1, color: PFColors.hairline),
                                _paymentTile(_payments[i]),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _paymentTile(Map<String, dynamic> payment) {
    final type = payment['payment_type']?.toString() ?? '';
    final status = payment['status']?.toString() ?? 'pending';
    final amount =
        double.tryParse(payment['amount']?.toString() ?? '0') ?? 0;
    final created = DateTime.tryParse(payment['created_at']?.toString() ?? '');
    final (icon, label, tint) = switch (type) {
      'premium' => (Icons.workspace_premium_rounded, 'Premium', PFColors.gold),
      'venue_booking' => (Icons.stadium_outlined, 'Venue booking', PFColors.primary),
      'match_share' => (Icons.sports_soccer_rounded, 'Match share', PFColors.success),
      _ => (Icons.payments_outlined, 'Payment', PFColors.textSecondary),
    };
    final statusColor = switch (status) {
      'success' => PFColors.success,
      'failed' => PFColors.danger,
      'refunded' => PFColors.warning,
      _ => PFColors.textSecondary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(PFRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  [
                    if (created != null) prettyDate(created.toLocal()),
                    payment['tx_ref']?.toString() ?? '',
                  ].where((part) => part.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: PFSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Br ${amount.toStringAsFixed(2)}',
                  style: PFType.number.copyWith(fontSize: 14)),
              const SizedBox(height: 3),
              PFBadge(label: status.toUpperCase(), color: statusColor),
            ],
          ),
        ],
      ),
    );
  }
}
