import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/services/payment_service.dart';
import '../../core/data/services/analytics_service.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';

class SubscriptionScreen extends StatefulWidget {
  final String token;
  const SubscriptionScreen({super.key, required this.token});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = true;
  bool _isPremium = false;
  String? _premiumExpires;
  bool _processing = false;

  static const _features = [
    'Unlimited host matches',
    'Unlimited teams',
    'Get ranked (Elo tracking)',
    'Join & create leagues',
    'Priority listing',
    'Premium badge',
    'Advanced stats',
    'Ad-free experience',
  ];

  @override
  void initState() {
    super.initState();
    AnalyticsService.event('premium_viewed', {'source': 'subscription_screen'});
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    final result = await PaymentService.getPaymentStatus(widget.token);
    if (!mounted) return;
    setState(() {
      _isPremium = result['is_premium'] ?? false;
      _premiumExpires = result['premium_expires'];
      _loading = false;
    });
  }

  Future<void> _subscribe() async {
    setState(() => _processing = true);
    final result = await PaymentService.initializePremium(token: widget.token);
    if (!mounted) return;
    setState(() => _processing = false);
    if (result['success'] == true && result['checkout_url'] != null) {
      final url = Uri.parse(result['checkout_url']);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Complete payment in the browser, then return here.')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result['message']?.toString() ?? 'Payment failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Victiqo Premium'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PFColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                PFCard(
                  padding: EdgeInsets.zero,
                  radius: PFRadius.xl,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(PFSpacing.xl),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          PFColors.primary.withValues(alpha: 0.16),
                          PFColors.surface,
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: PFColors.primary.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPremium ? Icons.diamond : Icons.diamond_outlined,
                            color: PFColors.primary,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: PFSpacing.lg),
                        Text(
                          _isPremium ? 'Premium active' : 'Go Premium',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isPremium && _premiumExpires != null
                              ? 'Expires ${_premiumExpires!.substring(0, 10)}'
                              : '100 ETB / month',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_isPremium) ...[
                  const SizedBox(height: PFSpacing.xxl),
                  Text('WHAT YOU GET', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: PFSpacing.md),
                  PFCard(
                    child: Column(
                      children: [
                        for (int i = 0; i < _features.length; i++) ...[
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: PFColors.primary, size: 20),
                              const SizedBox(width: PFSpacing.md),
                              Expanded(
                                child: Text(_features[i],
                                    style: Theme.of(context).textTheme.bodyLarge),
                              ),
                            ],
                          ),
                          if (i < _features.length - 1) const SizedBox(height: PFSpacing.md),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: (!_loading && !_isPremium)
          ? Container(
              decoration: const BoxDecoration(
                color: PFColors.surface,
                border: Border(top: BorderSide(color: PFColors.hairline)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: PFButton(
                    label: 'Subscribe — 100 ETB/month',
                    loading: _processing,
                    onTap: _subscribe,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
