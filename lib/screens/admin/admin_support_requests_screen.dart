import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import 'package:caddymoney/nav.dart';
import 'package:caddymoney/services/support_request_service.dart';
import 'package:caddymoney/models/support_request_model.dart';
import 'package:caddymoney/core/enums/support_request_status.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';
import 'package:caddymoney/widgets/admin_support_notifications_app_bar.dart';

class AdminSupportRequestsScreen extends StatefulWidget {
  const AdminSupportRequestsScreen({super.key});

  @override
  State<AdminSupportRequestsScreen> createState() => _AdminSupportRequestsScreenState();
}

class _AdminSupportRequestsScreenState extends State<AdminSupportRequestsScreen> {
  final _service = SupportRequestService();
  late Future<({List<SupportRequestModel> requests, String? error})> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.listAllRequestsForAdmin();
  }

  Future<void> _refresh() async {
    setState(() => _future = _service.listAllRequestsForAdmin());
    try {
      await _future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('MMM d • HH:mm');

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AdminSupportNotificationsAppBar(
          showLeading: true,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_outlined),
              onPressed: _refresh,
            ),
          ],
          // Wrap TabBar in a styled container so it is clearly visible and
          // reliably takes up space in the app bar.
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.25))),
              ),
              child: TabBar(
                splashFactory: NoSplash.splashFactory,
                dividerColor: Colors.transparent,
                labelColor: cs.onSurface,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                unselectedLabelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
                ),
                tabs: const [
                  Tab(text: 'New'),
                  Tab(text: 'In progress'),
                  Tab(text: 'Resolved'),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: FutureBuilder<({List<SupportRequestModel> requests, String? error})>(
            future: _future,
            builder: (context, snap) {
              final waiting = snap.connectionState == ConnectionState.waiting;
              final error = snap.data?.error;
              final items = snap.data?.requests ?? const <SupportRequestModel>[];

              if (waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError || ((error ?? '').isNotEmpty && items.isEmpty)) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppSpacing.paddingLg,
                    children: [
                      Text(
                        error ?? 'Failed to load support requests. Pull to refresh.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              }

              final newItems = items.where((e) => e.status == SupportRequestStatus.newRequest).toList(growable: false);
              final inProgressItems = items.where((e) => e.status == SupportRequestStatus.inProgress).toList(growable: false);
              final resolvedItems = items.where((e) => e.status == SupportRequestStatus.resolved).toList(growable: false);

              return TabBarView(
                children: [
                  _AdminSupportRequestsList(
                    title: 'Support Requests',
                    emptyText: 'No new requests yet.',
                    items: newItems,
                    fmt: fmt,
                    onRefresh: _refresh,
                  ),
                  _AdminSupportRequestsList(
                    title: 'Support Requests',
                    emptyText: 'No requests in progress.',
                    items: inProgressItems,
                    fmt: fmt,
                    onRefresh: _refresh,
                  ),
                  _AdminSupportRequestsList(
                    title: 'Support Requests',
                    emptyText: 'No resolved requests yet.',
                    items: resolvedItems,
                    fmt: fmt,
                    onRefresh: _refresh,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AdminSupportRequestsList extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<SupportRequestModel> items;
  final DateFormat fmt;
  final Future<void> Function() onRefresh;

  const _AdminSupportRequestsList({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.fmt,
    required this.onRefresh,
  });

  Future<void> _openDetailThenRefresh(BuildContext context, String requestId) async {
    await context.push('${AppRoutes.adminSupportRequests}/$requestId');
    await onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.paddingLg,
        itemCount: items.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  if (items.isEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(emptyText, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            );
          }

          if (items.isEmpty) return const SizedBox.shrink();

          final r = items[i - 1];
          final requesterName = (r.requesterDisplayName ?? '').trim();
          final requesterLabel = requesterName.isEmpty ? r.requesterType.displayName : '${r.requesterType.displayName} ($requesterName)';
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SupportRequestRow(
              ticketNumber: r.ticketNumber,
              subject: r.subject,
              subtitle: '$requesterLabel • ${r.status.displayName} • ${fmt.format(r.createdAt.toLocal())}',
              onTap: () => unawaited(_openDetailThenRefresh(context, r.id)),
            ),
          );
        },
      ),
    );
  }
}

class _SupportRequestRow extends StatelessWidget {
  final String ticketNumber;
  final String subject;
  final String subtitle;
  final VoidCallback onTap;

  const _SupportRequestRow({
    required this.ticketNumber,
    required this.subject,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: cs.outline),
            color: cs.surface,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.confirmation_number_outlined, color: cs.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ticketNumber, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(subject, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
