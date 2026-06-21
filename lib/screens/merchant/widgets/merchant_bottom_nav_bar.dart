import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';

import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/theme.dart';

/// Persistent bottom navigation for the **merchant** area.
///
/// Uses `go_router` navigation and highlights the current tab based on the
/// matched location.
class MerchantBottomNavBar extends StatelessWidget {
  const MerchantBottomNavBar({super.key});

  int _indexForLocation(String location) {
    if (location == AppRoutes.merchantDashboard) return 0;
    if (location == AppRoutes.merchantTransactions) return 1;
    if (location == AppRoutes.merchantSettings) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexForLocation(location);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // More transparent “glass” tint so content can be seen underneath.
    // Dark mode needs a slightly higher alpha than light mode for legibility.
    final backgroundTint = cs.surface.withValues(alpha: isDark ? 0.32 : 0.22);

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.xl),
          topRight: Radius.circular(AppRadius.xl),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            decoration: BoxDecoration(
              color: backgroundTint,
              border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: isDark ? 0.18 : 0.12))),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: isDark ? 0.22 : 0.06),
                  blurRadius: 32,
                  spreadRadius: -16,
                  offset: const Offset(0, -12),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _MerchantBottomNavItem(
                    selected: selectedIndex == 0,
                    icon: Icons.home_outlined,
                    label: l10n.home,
                    selectedColor: cs.primary,
                    onTap: () => context.go(AppRoutes.merchantDashboard),
                  ),
                ),
                Expanded(
                  child: _MerchantBottomNavItem(
                    selected: selectedIndex == 1,
                    icon: Icons.sync_alt_rounded,
                    label: l10n.transactions,
                    selectedColor: cs.primary,
                    onTap: () => context.go(AppRoutes.merchantTransactions),
                  ),
                ),
                Expanded(
                  child: _MerchantBottomNavItem(
                    selected: selectedIndex == 2,
                    icon: Icons.settings_outlined,
                    label: l10n.settings,
                    selectedColor: cs.primary,
                    onTap: () => context.go(AppRoutes.merchantSettings),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MerchantBottomNavItem extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final Color selectedColor;
  final VoidCallback onTap;

  const _MerchantBottomNavItem({required this.selected, required this.icon, required this.label, required this.selectedColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = selected ? selectedColor : cs.onSurfaceVariant;
    final textColor = selected ? selectedColor : cs.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
