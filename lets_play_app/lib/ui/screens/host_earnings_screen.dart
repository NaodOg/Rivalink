import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/data/services/analytics_service.dart';
import '../../core/data/services/host_earnings_service.dart';
import '../../core/theme/rivalink_theme.dart';
import '../../core/utils/formatters.dart';
import '../widgets/pf_badge.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_scaffold.dart';
import '../widgets/pf_section_header.dart';

class HostEarningsScreen extends StatefulWidget {
  final String token;
  const HostEarningsScreen({super.key, required this.token});

  @override
  State<HostEarningsScreen> createState() => _HostEarningsScreenState();
}

class _HostEarningsScreenState extends State<HostEarningsScreen> {
  Map<String, dynamic> _account = {};
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _payouts = [];
  bool _loading = true;
  bool _error = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.event('host_earnings_viewed');
    _load();
  }

  double get _available => _num(_account['available']);
  double get _minimum => _num(_account['minimum_payout']);

  Map<String, dynamic>? get _pendingPayout {
    for (final payout in _payouts) {
      if (payout['status'] == 'requested' || payout['status'] == 'processing') {
        return payout;
      }
    }
    return null;
  }

  bool get _canRequest =>
      _available >= _minimum &&
      _pendingPayout == null &&
      _account['has_payout_in_progress'] != true;

  Future<void> _load() async {
    final firstLoad = _account.isEmpty;
    setState(() {
      _loading = firstLoad;
      _error = false;
    });
    final data = await HostEarningsService.getEarnings(widget.token);
    if (!mounted) return;
    if (data['success'] == true) {
      setState(() {
        _account = Map<String, dynamic>.from(data['account'] ?? {});
        _ledger = ((data['ledger'] as List?) ?? const [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _payouts = ((data['payouts'] as List?) ?? const [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _requestPayout() async {
    final amountController = TextEditingController(
        text: _available >= _minimum ? _available.toStringAsFixed(2) : '');
    final destinationController = TextEditingController();
    final noteController = TextEditingController();
    var method = 'telebirr';

    final request = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: PFColors.surfaceRaised,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PFRadius.lg)),
          title: const Text('Request payout'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available ${_br(_available)}. Minimum ${_br(_minimum)}.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: PFSpacing.md),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: 'Br ',
                  ),
                ),
                const SizedBox(height: PFSpacing.md),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(labelText: 'Send to'),
                  items: const [
                    DropdownMenuItem(
                        value: 'telebirr', child: Text('Telebirr')),
                    DropdownMenuItem(
                        value: 'bank', child: Text('Bank transfer')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => method = value);
                  },
                ),
                const SizedBox(height: PFSpacing.md),
                TextField(
                  controller: destinationController,
                  decoration: InputDecoration(
                    labelText: method == 'bank'
                        ? 'Bank account number'
                        : (method == 'telebirr'
                            ? 'Telebirr number'
                            : 'Destination details'),
                    hintText: method == 'bank'
                        ? 'e.g. 1000123456789'
                        : 'e.g. 0911223344',
                  ),
                ),
                const SizedBox(height: PFSpacing.md),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text.trim());
                final destination = destinationController.text.trim();
                if (amount == null || amount <= 0) {
                  _toast(ctx, 'Enter a valid amount');
                  return;
                }
                if (amount < _minimum) {
                  _toast(ctx, 'Minimum payout is ${_br(_minimum)}');
                  return;
                }
                if (amount > _available) {
                  _toast(ctx, 'Amount exceeds your available balance');
                  return;
                }
                if (method != 'other' && destination.isEmpty) {
                  _toast(ctx, 'Enter where the money should be sent');
                  return;
                }
                Navigator.pop(ctx, {
                  'amount': amount.toStringAsFixed(2),
                  'method': method,
                  'destination': destination,
                  'note': noteController.text.trim(),
                });
              },
              child: const Text('Request'),
            ),
          ],
        ),
      ),
    );

    amountController.dispose();
    destinationController.dispose();
    noteController.dispose();
    if (request == null || !mounted) return;

    setState(() => _working = true);
    final result = await HostEarningsService.requestPayout(
      token: widget.token,
      amount: request['amount']!,
      method: request['method']!,
      destination: request['destination']!,
      note: request['note'] ?? '',
    );
    if (!mounted) return;
    setState(() => _working = false);
    _toast(context, result['success'] == true
        ? 'Payout requested — the team will review it'
        : (result['message']?.toString() ?? 'Could not request payout'));
    if (result['success'] == true) _load();
  }

  Future<void> _cancelPayout(Map<String, dynamic> payout) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PFColors.surfaceRaised,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PFRadius.lg)),
        title: const Text('Cancel this payout?'),
        content: Text(
            '${_br(_num(payout['amount']))} will return to your available balance.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel payout',
                  style: TextStyle(color: PFColors.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _working = true);
    final result = await HostEarningsService.cancelPayout(
      token: widget.token,
      payoutId: payout['id'] as int,
    );
    if (!mounted) return;
    setState(() => _working = false);
    _toast(context,
        result['success'] == true ? 'Payout cancelled' : 'Could not cancel payout');
    if (result['success'] == true) _load();
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Host earnings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
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
                        title: 'Could not load earnings',
                        message: 'Check your connection and try again.',
                        actionLabel: 'Retry',
                        onAction: _load,
                      ),
                    ],
                  )
                : ListView(
                    padding:
                        const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _balanceHero(context),
                      const SizedBox(height: PFSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: _statTile(
                              context,
                              icon: Icons.schedule_rounded,
                              tint: PFColors.warning,
                              label: 'Pending payout',
                              value: _br(_num(_account['pending'])),
                            ),
                          ),
                          const SizedBox(width: PFSpacing.md),
                          Expanded(
                            child: _statTile(
                              context,
                              icon: Icons.check_circle_outline_rounded,
                              tint: PFColors.success,
                              label: 'Paid out',
                              value: _br(_num(_account['paid_out'])),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: PFSpacing.lg),
                      if (_pendingPayout != null) ...[
                        _pendingCard(context, _pendingPayout!),
                        const SizedBox(height: PFSpacing.lg),
                      ],
                      PFButton(
                        label: _pendingPayout != null
                            ? 'Payout in progress'
                            : 'Request payout',
                        icon: Icons.account_balance_wallet_outlined,
                        onTap: _canRequest && !_working ? _requestPayout : null,
                        loading: _working,
                      ),
                      if (!_canRequest && _pendingPayout == null) ...[
                        const SizedBox(height: PFSpacing.sm),
                        Text(
                          _available < _minimum
                              ? 'You need at least ${_br(_minimum)} available to withdraw.'
                              : 'Finish the current payout before requesting another.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: PFSpacing.xxl),
                      PFSectionHeader(
                        eyebrow: 'Ledger',
                        title: 'Recent activity',
                        accent: PFColors.primary,
                      ),
                      const SizedBox(height: PFSpacing.md),
                      if (_ledger.isEmpty)
                        const PFEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No earnings yet',
                          message:
                              'Released match shares and no-show forfeits will appear here.',
                        )
                      else
                        PFCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          child: Column(
                            children: [
                              for (var i = 0; i < _ledger.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                      height: 1, color: PFColors.hairline),
                                _ledgerTile(_ledger[i]),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: PFSpacing.xxl),
                      PFSectionHeader(
                        eyebrow: 'Withdrawals',
                        title: 'Payout history',
                        accent: PFColors.success,
                      ),
                      const SizedBox(height: PFSpacing.md),
                      if (_payouts.isEmpty)
                        Text(
                          'No payout requests yet. Your first request will show here with its transfer reference.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        PFCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          child: Column(
                            children: [
                              for (var i = 0; i < _payouts.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                      height: 1, color: PFColors.hairline),
                                _payoutTile(_payouts[i]),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: PFSpacing.lg),
                      Text(
                        'Released shares become available to withdraw. '
                        '“Paid out” means the transfer has left Victiqo and the '
                        'reference is recorded.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _balanceHero(BuildContext context) {
    final available = _num(_account['available']);
    final negative = available < 0;
    return Container(
      padding: const EdgeInsets.all(PFSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PFRadius.xl),
        border: Border.all(color: PFColors.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (negative ? PFColors.danger : PFColors.primary)
                .withValues(alpha: 0.20),
            PFColors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('AVAILABLE TO WITHDRAW',
                  style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              PFBadge(
                label: negative ? 'Balance owed' : 'Ready',
                color: negative ? PFColors.danger : PFColors.success,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _br(available),
            style: PFType.number.copyWith(
              fontSize: 40,
              color: negative ? PFColors.danger : PFColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            negative
                ? 'Future match releases will first cover the refunds Victiqo fronted.'
                : 'Minimum withdrawal ${_br(_minimum)} · reviewed by the Victiqo team',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _statTile(
    BuildContext context, {
    required IconData icon,
    required Color tint,
    required String label,
    required String value,
  }) {
    return PFCard(
      padding: const EdgeInsets.all(PFSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(PFRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(height: 10),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(value,
              style: PFType.number.copyWith(fontSize: 17),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _pendingCard(BuildContext context, Map<String, dynamic> payout) {
    final requested = _dateLabel(payout['requested_at']);
    return PFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top_rounded,
                  color: PFColors.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Payout ${_br(_num(payout['amount']))}',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              PFBadge(
                label: (payout['status']?.toString() ?? 'requested')
                    .toUpperCase(),
                color: PFColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_methodLabel(payout['method'])} · ${payout['destination'] ?? ''}'
            '${requested.isNotEmpty ? ' · $requested' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (payout['status'] == 'requested') ...[
            const SizedBox(height: PFSpacing.md),
            PFButton(
              label: 'Cancel request',
              variant: PFButtonVariant.secondary,
              dense: true,
              onTap: _working ? null : () => _cancelPayout(payout),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ledgerTile(Map<String, dynamic> entry) {
    final amount = _num(entry['amount']);
    final positive = amount >= 0;
    final kind = entry['kind']?.toString() ?? '';
    final (icon, tint) = _kindStyle(kind);
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
                Text(_kindLabel(kind),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  [
                    if (entry['match_title'] != null) entry['match_title'],
                    if ((entry['note']?.toString() ?? '').isNotEmpty)
                      entry['note'],
                    _dateLabel(entry['created_at']),
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
            '${positive ? '+' : ''}${_br(amount)}',
            style: PFType.number.copyWith(
              fontSize: 14,
              color: positive ? PFColors.success : PFColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _payoutTile(Map<String, dynamic> payout) {
    final status = payout['status']?.toString() ?? 'requested';
    final color = switch (status) {
      'paid' => PFColors.success,
      'rejected' => PFColors.danger,
      'processing' => PFColors.secondary,
      'cancelled' => PFColors.textSecondary,
      _ => PFColors.warning,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(_br(_num(payout['amount'])),
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(width: 8),
                    PFBadge(label: status.toUpperCase(), color: color),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    _methodLabel(payout['method']),
                    if ((payout['destination']?.toString() ?? '').isNotEmpty)
                      payout['destination'],
                    _dateLabel(payout['requested_at']),
                  ].where((part) => part != null && part.toString().isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if ((payout['reference']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Ref: ${payout['reference']}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                if (status == 'rejected' &&
                    (payout['admin_note']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(payout['admin_note'].toString(),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _kindStyle(String kind) {
    switch (kind) {
      case 'match_release':
        return (Icons.sports_soccer_rounded, PFColors.success);
      case 'no_show_forfeit':
        return (Icons.person_off_rounded, PFColors.success);
      case 'venue_release':
        return (Icons.stadium_outlined, PFColors.success);
      case 'payout_request':
        return (Icons.account_balance_wallet_rounded, PFColors.secondary);
      case 'payout_rejected':
      case 'payout_cancelled':
        return (Icons.undo_rounded, PFColors.warning);
      case 'cancellation_clawback':
        return (Icons.gavel_rounded, PFColors.danger);
      default:
        return (Icons.tune_rounded, PFColors.textSecondary);
    }
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'match_release':
        return 'Match share released';
      case 'no_show_forfeit':
        return 'No-show forfeited';
      case 'venue_release':
        return 'Venue booking paid';
      case 'payout_request':
        return 'Payout requested';
      case 'payout_rejected':
        return 'Payout returned';
      case 'payout_cancelled':
        return 'Payout cancelled';
      case 'cancellation_clawback':
        return 'Cancellation clawback';
      default:
        return 'Adjustment';
    }
  }

  String _methodLabel(dynamic method) {
    switch (method?.toString()) {
      case 'bank':
        return 'Bank transfer';
      case 'telebirr':
        return 'Telebirr';
      default:
        return 'Other';
    }
  }

  String _dateLabel(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return prettyDate(parsed.toLocal());
  }

  double _num(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  String _br(double value) {
    final sign = value < 0 ? '-' : '';
    return '${sign}Br ${value.abs().toStringAsFixed(2)}';
  }
}
