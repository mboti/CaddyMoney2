import 'package:flutter/material.dart';

import 'package:caddymoney/core/theme/app_colors.dart';

/// Provides a consistent brand-styled theme for [showDateRangePicker].
///
/// We keep this isolated so we can style the picker (range highlight, start/end
/// circles, header) without affecting the rest of the app theme.
ThemeData buildBrandDateRangePickerTheme(BuildContext context) {
  final base = Theme.of(context);
  final cs = base.colorScheme;
  const brand = AppColors.brandPurple;

  // Material DateRangePicker uses `primary` for the start/end day background.
  // The in-between range uses `rangeSelectionBackgroundColor`.
  return base.copyWith(
    colorScheme: cs.copyWith(primary: brand, secondary: brand),
    datePickerTheme: base.datePickerTheme.copyWith(
      rangeSelectionBackgroundColor: brand.withValues(alpha: 0.22),
      rangeSelectionOverlayColor: const WidgetStatePropertyAll(Colors.transparent),
      dayOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed) || states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
          return brand.withValues(alpha: 0.10);
        }
        return null;
      }),
    ),
  );
}
