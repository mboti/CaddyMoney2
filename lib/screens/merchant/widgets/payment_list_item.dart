import 'package:flutter/material.dart';

import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/core/utils/transaction_reference.dart';
import 'package:caddymoney/theme.dart';

class PaymentListItem extends StatelessWidget {
  final double amount;
  final String date;
  final String paymentId;
  final String currencyCode;

  const PaymentListItem({
    super.key,
    required this.amount,
    required this.date,
    required this.paymentId,
    this.currencyCode = 'EUR',
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.15)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  shortenTransactionReference(paymentId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.15),
                ),
              ],
            ),
          ),
          Text(
            '+${amount.toStringAsFixed(2)}${_currencySuffix(currencyCode)}',
            style: textTheme.titleLarge?.copyWith(color: AppColors.success, fontWeight: FontWeight.w800, height: 1.05),
          ),
        ],
      ),
    );
  }
}

String _currencySuffix(String code) {
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
