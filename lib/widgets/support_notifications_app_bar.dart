import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/services/support_request_service.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';
import 'package:caddymoney/screens/support/support_center_screen.dart';

/// A [CaddyMoneyTopAppBar] that shows a badge when support has responded.
///
/// The badge is derived from `support_requests` rows where:
/// - requester_profile_id == current user
/// - requester_type matches
/// - admin_response is not null
/// - requester_seen_at is null
class SupportNotificationsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showLeading;
  final SupportRequesterType requesterType;

  const SupportNotificationsAppBar({
    super.key,
    required this.requesterType,
    this.showLeading = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final uid = SupabaseConfig.auth.currentUser?.id;
    if (uid == null) {
      return CaddyMoneyTopAppBar(
        showLeading: showLeading,
        onNotificationsTap: () async {
          // When the user taps the bell, treat it as "I opened support" and
          // persist the seen state right away.
          await SupportRequestService().markAllMyAdminResponsesSeen(requesterType: requesterType);
          if (!context.mounted) return;
          context.push(AppRoutes.supportCenter, extra: SupportCenterArgs(requesterType: requesterType, initialTabIndex: 1));
        },
      );
    }

    final service = SupportRequestService();
    // IMPORTANT: Provide a computation for Stream.periodic when T is non-nullable.
    // Otherwise the stream tries to emit `null` and Flutter throws:
    // "Invalid argument (computation): Must not be omitted when the event type is non-nullable: null"
    final poll = Stream<int>.periodic(const Duration(seconds: 3), (i) => i)
        .asyncMap((_) => service.countUnreadAdminResponses(requesterType: requesterType));

    return PreferredSize(
      preferredSize: preferredSize,
      child: StreamBuilder<int>(
        stream: poll,
        initialData: 0,
        builder: (context, snap) {
          return CaddyMoneyTopAppBar(
            showLeading: showLeading,
            notificationCount: snap.data ?? 0,
            onNotificationsTap: () async {
              await SupportRequestService().markAllMyAdminResponsesSeen(requesterType: requesterType);
              if (!context.mounted) return;
              context.push(AppRoutes.supportCenter, extra: SupportCenterArgs(requesterType: requesterType, initialTabIndex: 1));
            },
          );
        },
      ),
    );
  }
}
