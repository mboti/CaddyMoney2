import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:caddymoney/nav.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/screens/user/widgets/user_bottom_nav_bar.dart';
import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';

class PayMerchantScreen extends StatelessWidget {
  const PayMerchantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const CaddyMoneyTopAppBar(showLeading: false),
      bottomNavigationBar: const UserBottomNavBar(),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.center,
                child: Text(
                  'Pay',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Pay at a merchant', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: AppSpacing.paddingLg,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.qr_code_scanner_outlined, color: cs.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Scan a QR code', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Coming soon: scan a merchant QR code to pay for items using your assigned service balance.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.push(AppRoutes.qrScan);
                  },
                  icon: Icon(Icons.qr_code_scanner_outlined, color: cs.onSurface),
                  label: Text(AppLocalizations.of(context)?.openScanner ?? 'Open scanner'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
