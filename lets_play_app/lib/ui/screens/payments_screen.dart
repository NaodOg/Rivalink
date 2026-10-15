import 'package:flutter/material.dart';

import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Payments'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          PFCard(
            raised: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WALLET BALANCE', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 8),
                Text('Br 2,450',
                    style: PFType.number.copyWith(fontSize: 32, color: PFColors.text)),
                const SizedBox(height: 6),
                Text('Ready for Telebirr, Chapa and cards.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: PFSpacing.lg),
          Text('RECENT ACTIVITY', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: PFSpacing.sm),
          PFCard(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
            child: Column(
              children: const [
                _TxnTile(title: 'Bole Stadium booking', amount: '-Br 1,500', date: 'Today'),
                Divider(height: 1, color: PFColors.hairline),
                _TxnTile(title: 'Match fee split', amount: '-Br 250', date: 'Yesterday'),
                Divider(height: 1, color: PFColors.hairline),
                _TxnTile(title: 'League prize reward', amount: '+Br 3,000', date: '2 days ago'),
              ],
            ),
          ),
          const SizedBox(height: PFSpacing.lg),
          PFButton(
            label: 'Add payment method',
            variant: PFButtonVariant.secondary,
            icon: Icons.add_card_rounded,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final String title;
  final String amount;
  final String date;
  const _TxnTile({required this.title, required this.amount, required this.date});

  @override
  Widget build(BuildContext context) {
    final plus = amount.startsWith('+');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (plus ? PFColors.success : PFColors.textTertiary).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(PFRadius.sm),
            ),
            child: Icon(plus ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 18, color: plus ? PFColors.success : PFColors.textSecondary),
          ),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(date, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(amount,
              style: PFType.number.copyWith(
                  fontSize: 14, color: plus ? PFColors.success : PFColors.text)),
        ],
      ),
    );
  }
}
