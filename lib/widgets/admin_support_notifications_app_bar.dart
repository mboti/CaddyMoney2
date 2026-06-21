import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:caddymoney/nav.dart';
import 'package:caddymoney/services/support_request_service.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';

/// Admin variant of the top app bar that shows a red-dot badge when new
/// support requests are waiting.
class AdminSupportNotificationsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showLeading;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const AdminSupportNotificationsAppBar({
    super.key,
    this.showLeading = true,
    this.leading,
    this.actions,
    this.bottom,
  });

  @override
  Size get preferredSize {
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomHeight);
  }

  @override
  Widget build(BuildContext context) {
    final service = SupportRequestService();

    // IMPORTANT: Provide a computation for Stream.periodic when T is non-nullable.
    // Otherwise the stream tries to emit `null` and Flutter throws:
    // "Invalid argument (computation): Must not be omitted when the event type is non-nullable: null"
    final poll = Stream<int>.periodic(const Duration(seconds: 3), (i) => i)
        .asyncMap((_) => service.countNewRequestsForAdmin());

    // Wrap the StreamBuilder in a PreferredSize so Scaffold reliably measures
    // the app bar (including any `bottom` like TabBar).
    return PreferredSize(
      preferredSize: preferredSize,
      child: StreamBuilder<int>(
        stream: poll,
        initialData: 0,
        builder: (context, snap) {
          return CaddyMoneyTopAppBar(
            showLeading: showLeading,
            leading: leading,
            actions: actions,
            bottom: bottom,
            notificationCount: snap.data ?? 0,
            onNotificationsTap: () => context.push(AppRoutes.adminSupportRequests),
          );
        },
      ),
    );
  }
}
