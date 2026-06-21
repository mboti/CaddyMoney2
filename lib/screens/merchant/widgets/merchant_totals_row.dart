import 'package:flutter/material.dart';

import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/theme.dart';

/// Displays the merchant's transaction totals as two side-by-side stat cards:
/// - Total received
/// - Number of transactions
class MerchantTotalsRow extends StatelessWidget {
  final double totalReceived;
  final int transactionCount;
  final String currencyCode;
  final bool isLoading;

  const MerchantTotalsRow({super.key, required this.totalReceived, required this.transactionCount, required this.currencyCode, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final currency = currencyCode;
    return Row(
      children: [
        Expanded(
          child: MerchantStatCard(
            title: 'Total Received',
            value: isLoading ? '—' : '${totalReceived.toStringAsFixed(2)}${currencySuffix(currency)}',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: MerchantStatCard(
            title: 'Transactions',
            value: isLoading ? '—' : '$transactionCount',
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class MerchantStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData? icon;
  final Color color;

  const MerchantStatCard({
    super.key,
    required this.title,
    required this.value,
    this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: color, size: 16),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.05),
          ),
        ],
      ),
    );
  }
}

String currencySuffix(String code) {
  switch (code.toUpperCase()) {
    case 'EUR':
      return '€';
    case 'USD':
      return r'$';
    case 'GBP':
      return '£';
    default:
      return '';
  }
}
