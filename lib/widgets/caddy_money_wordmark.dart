import 'package:flutter/material.dart';

import 'package:caddymoney/core/theme/app_colors.dart';

/// Branded app wordmark: **Caddy** (theme-dependent) + **Money** (brand purple).
class CaddyMoneyWordmark extends StatelessWidget {
  const CaddyMoneyWordmark({super.key, this.style, this.caddyColor, this.moneyColor, this.textAlign});

  /// Base style applied to both spans.
  final TextStyle? style;

  /// Color for the “Caddy” part. Defaults to `colorScheme.onSurface`.
  final Color? caddyColor;

  /// Color for the “Money” part. Defaults to [AppColors.brandPurple].
  final Color? moneyColor;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final cs = Theme.of(context).colorScheme;
    final resolvedCaddy = caddyColor ?? cs.onSurface;
    final resolvedMoney = moneyColor ?? AppColors.brandPurple;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Caddy', style: baseStyle.copyWith(color: resolvedCaddy)),
          TextSpan(text: 'Money', style: baseStyle.copyWith(color: resolvedMoney)),
        ],
      ),
      textAlign: textAlign,
      semanticsLabel: 'CaddyMoney',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
