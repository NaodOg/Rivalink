import 'package:flutter/material.dart';

import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

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
      body: ListView(
        children: [
          const PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Wallet Balance', style: TextStyle(color: PFColors.muted)),
                SizedBox(height: 6),
                Text('Br 2,450', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text('Payment rails ready for Telebirr, Chapa, Stripe.', style: TextStyle(color: PFColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const PFCard(
            child: Column(
              children: [
                _TxnTile(title: 'Bole Stadium Booking', amount: '-Br 1,500', date: 'Today'),
                _TxnTile(title: 'Match Fee Split', amount: '-Br 250', date: 'Yesterday'),
                _TxnTile(title: 'League Prize Reward', amount: '+Br 3,000', date: '2 days ago'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PFButton(label: 'Add Payment Method', onTap: () {}),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(date, style: const TextStyle(color: PFColors.muted)),
      trailing: Text(amount, style: TextStyle(color: plus ? PFColors.accent : PFColors.text, fontWeight: FontWeight.w700)),
    );
  }
}
