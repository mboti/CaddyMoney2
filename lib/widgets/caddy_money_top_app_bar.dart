import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:caddymoney/widgets/caddy_money_wordmark.dart';
import 'package:caddymoney/providers/auth_provider.dart';

/// A branded top app bar that matches the Home screen:
/// - Left title: **CaddyMoney** wordmark (Caddy = onSurface, Money = brand green)
/// - Right action: notification bell
///
/// Use [actions] to inject extra action buttons *before* the bell.
class CaddyMoneyTopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CaddyMoneyTopAppBar({
    super.key,
    this.showLeading = true,
    this.leading,
    this.actions,
    this.onNotificationsTap,
    this.notificationCount,
    this.showSignOut = true,
    this.bottom,
  });

  final bool showLeading;

  /// Optional custom leading widget (e.g., a back button).
  ///
  /// If provided, it will be used and Flutter won't auto-infer one.
  final Widget? leading;

  /// Extra action widgets to render before the notification bell.
  final List<Widget>? actions;

  final VoidCallback? onNotificationsTap;

  /// Optional unread count. If > 0, a small badge is shown on the bell.
  final int? notificationCount;

  /// Whether to show an icon-only sign out action (to the left of the bell).
  ///
  /// Defaults to true, but will auto-hide if no signed-in user is present.
  final bool showSignOut;

  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;

    final resolvedLeading = showLeading ? leading : null;
    final implyLeading = showLeading && resolvedLeading == null;

    final authProvider = context.watch<AuthProvider>();
    final canShowSignOut = showSignOut && authProvider.currentUser != null;

    Future<void> signOut() async {
      try {
        await context.read<AuthProvider>().signOut();
        if (context.mounted) context.go('/role-selection');
      } catch (e) {
        debugPrint('Sign out failed: $e');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to sign out. Please try again.')));
      }
    }

    return AppBar(
      automaticallyImplyLeading: implyLeading,
      leading: resolvedLeading,
      titleSpacing: NavigationToolbar.kMiddleSpacing,
      title: CaddyMoneyWordmark(style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      actions: [
        ...?actions,
        if (canShowSignOut) ...[
          IconButton(
            tooltip: 'Sign out',
            onPressed: signOut,
            style: IconButton.styleFrom(splashFactory: NoSplash.splashFactory),
            icon: Icon(Icons.logout_rounded, color: accent),
          ),
          const SizedBox(width: 10),
        ],
        IconButton(
          tooltip: 'Notifications',
          onPressed: onNotificationsTap ??
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications coming soon.')),
                );
              },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.notifications_none_rounded, color: accent),
              if ((notificationCount ?? 0) > 0)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: cs.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 1.2),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
      ],
      bottom: bottom,
    );
  }
}
