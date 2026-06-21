import 'package:flutter/material.dart';
import 'package:caddymoney/core/enums/merchant_status.dart';
import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/theme.dart';

/// A compact status chip for merchant approval state (Pending / Approved / etc.).
class MerchantStatusBadge extends StatelessWidget {
  final MerchantStatus? merchantStatus;

  const MerchantStatusBadge({super.key, required this.merchantStatus});

  @override
  Widget build(BuildContext context) {
    final (label, icon, fg, bg) = _styleFor(merchantStatus);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  (String, IconData, Color, Color) _styleFor(MerchantStatus? status) {
    switch (status) {
      case MerchantStatus.approved:
        return (
          MerchantStatus.approved.displayName,
          Icons.check_circle_outline,
          AppColors.successDark,
          AppColors.success.withValues(alpha: 0.12),
        );
      case MerchantStatus.pending:
        return (
          'Pending',
          Icons.hourglass_bottom,
          AppColors.warningDark,
          AppColors.warning.withValues(alpha: 0.12),
        );
      case MerchantStatus.rejected:
        return (
          MerchantStatus.rejected.displayName,
          Icons.cancel_outlined,
          AppColors.errorDark,
          AppColors.error.withValues(alpha: 0.12),
        );
      case MerchantStatus.suspended:
        return (
          MerchantStatus.suspended.displayName,
          Icons.pause_circle_outline,
          AppColors.errorDark,
          AppColors.error.withValues(alpha: 0.12),
        );
      case null:
        return ('—', Icons.info_outline, AppColors.warningDark, AppColors.warning.withValues(alpha: 0.12));
    }
  }
}
