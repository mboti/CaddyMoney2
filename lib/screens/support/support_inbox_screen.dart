import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';
import 'package:caddymoney/models/support_request_model.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/services/support_request_service.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';

class SupportInboxScreen extends StatefulWidget {
  final SupportRequesterType? requesterType;

  const SupportInboxScreen({super.key, this.requesterType});

  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen> {
  final GlobalKey<SupportInboxBodyState> _bodyKey = GlobalKey<SupportInboxBodyState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bodyKey.currentState?.acknowledgeAllAsSeen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CaddyMoneyTopAppBar(showLeading: true),
      body: SafeArea(
        child: SupportInboxBody(key: _bodyKey, requesterType: widget.requesterType),
      ),
    );
  }
}

/// Inbox list content for support responses/status.
///
/// Can be embedded (e.g. in a tab view) or used inside a full screen scaffold.
class SupportInboxBody extends StatefulWidget {
  final EdgeInsets padding;
  final SupportRequesterType? requesterType;

  const SupportInboxBody({super.key, this.padding = AppSpacing.paddingLg, this.requesterType});

  @override
  State<SupportInboxBody> createState() => SupportInboxBodyState();
}

class SupportInboxBodyState extends State<SupportInboxBody> {
  final _service = SupportRequestService();
  late Future<({List<SupportRequestModel> requests, String? error})> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.listMyRequests(limit: 200, requesterType: widget.requesterType);
  }

  /// Call this when the user *actually opens the inbox UI*.
  ///
  /// This persists the seen state in Supabase so the bell dot does not return
  /// after reconnect.
  Future<void> acknowledgeAllAsSeen() async {
    final requesterType = widget.requesterType;
    if (requesterType == null) return;
    await _service.markAllMyAdminResponsesSeen(requesterType: requesterType);
    if (!mounted) return;
    setState(() => _future = _service.listMyRequests(limit: 200, requesterType: requesterType));
  }

  Future<void> refresh() async {
    setState(() => _future = _service.listMyRequests(limit: 200, requesterType: widget.requesterType));
    try {
      await _future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final uid = SupabaseConfig.auth.currentUser?.id;
    final cs = Theme.of(context).colorScheme;
    if (uid == null) {
      return Center(
        child: Text('Please sign in to view notifications.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      );
    }

    // We treat “support responses / status updates” as notifications.
    return RefreshIndicator(
      onRefresh: refresh,
      child: FutureBuilder<({List<SupportRequestModel> requests, String? error})>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final err = snap.data?.error;
          final items = snap.data?.requests ?? const <SupportRequestModel>[];
          if (snap.hasError || err != null) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: widget.padding,
              children: [
                Text(err ?? 'Failed to load notifications. Pull to refresh.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            );
          }

          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: widget.padding,
              children: [
                Text('No notifications yet.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'When support responds to your request, you’ll see it here.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) {
              final r = items[i];
              return _SupportNotificationCard(
                request: r,
                onTap: () async {
                  if (!context.mounted) return;
                  context.push('${AppRoutes.supportInbox}/${r.id}');
                },
              );
            },
          );
        },
      ),
    );
  }
}

class SupportInboxDetailScreen extends StatefulWidget {
  final String requestId;
  const SupportInboxDetailScreen({super.key, required this.requestId});

  @override
  State<SupportInboxDetailScreen> createState() => _SupportInboxDetailScreenState();
}

class _SupportInboxDetailScreenState extends State<SupportInboxDetailScreen> {
  final _service = SupportRequestService();
  late Future<({SupportRequestModel? request, String? error})> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.getRequestById(widget.requestId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _service.getRequestById(widget.requestId);
    });
    try {
      await _future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('MMM d, yyyy • HH:mm');

    return Scaffold(
      appBar: const CaddyMoneyTopAppBar(showLeading: true),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<({SupportRequestModel? request, String? error})>(
            future: _future,
            builder: (context, snap) {
              final waiting = snap.connectionState == ConnectionState.waiting;
              if (waiting) return const Center(child: CircularProgressIndicator());
              final r = snap.data?.request;
              final err = snap.data?.error;
              if (snap.hasError || r == null) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppSpacing.paddingLg,
                  children: [
                    Text(err ?? 'Notification not found. Pull to refresh.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                );
              }

              // If the admin response exists, mark as seen when the detail screen opens.
              if ((r.adminResponse ?? '').trim().isNotEmpty && r.requesterSeenAt == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _service.markRequesterSeen(r.id));
              }

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppSpacing.paddingLg,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.ticketNumber,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      _StatusPill(text: r.status.displayName),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${r.requesterType.displayName} • ${fmt.format(r.createdAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Subject', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(text: r.subject),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Your message', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(text: r.description),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Support response', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(text: (r.adminResponse ?? '').trim().isEmpty ? 'No response yet.' : r.adminResponse!.trim()),
                  if (r.respondedAt != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Updated: ${fmt.format(r.respondedAt!.toLocal())}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SupportNotificationCard extends StatelessWidget {
  final SupportRequestModel request;
  final VoidCallback onTap;
  const _SupportNotificationCard({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasResponse = (request.adminResponse ?? '').trim().isNotEmpty;
    final isUnread = hasResponse && request.requesterSeenAt == null;
    final fmt = DateFormat('MMM d');
    final subtitle = hasResponse
        ? (request.adminResponse ?? '').trim().replaceAll('\n', ' ')
        : 'Status: ${request.status.displayName}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isUnread ? cs.primary.withValues(alpha: 0.12) : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(hasResponse ? Icons.mark_email_read_outlined : Icons.support_agent_outlined, color: isUnread ? cs.primary : cs.onSurfaceVariant),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            request.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          fmt.format((request.respondedAt ?? request.updatedAt).toLocal()),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _TinyPill(text: request.ticketNumber),
                        _TinyPill(text: request.status.displayName),
                        if (isUnread) _UnreadDot(),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  final String text;
  const _TinyPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outline.withValues(alpha: 0.45)),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  const _InfoCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outline),
        color: cs.surface,
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outline),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800),
      ),
    );
  }
}
