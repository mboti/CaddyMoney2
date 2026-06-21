import 'package:flutter/material.dart';

import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/theme.dart';

/// Merchant identity summary card (Merchant ID + Business + Category).
///
/// Used on merchant-related surfaces (e.g., Settings) to help the merchant
/// quickly find the information they may need for support/verification.
class MerchantIdentityCard extends StatelessWidget {
  final String merchantId;
  final String businessName;
  final String category;

  const MerchantIdentityCard({
    super.key,
    required this.merchantId,
    required this.businessName,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradientColors = isDark ? const [AppColors.primaryDark, AppColors.primary] : const [AppColors.transactionFilterSelectedPurple, AppColors.primaryLight];
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.06), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Merchant ID', style: tt.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
          const SizedBox(height: AppSpacing.xs),
          Text(merchantId, style: tt.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Business', style: tt.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                    Text(businessName, style: tt.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Category', style: tt.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                  Text(category, style: tt.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
