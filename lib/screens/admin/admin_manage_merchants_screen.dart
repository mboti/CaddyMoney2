import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:caddymoney/models/merchant_model.dart';
import 'package:caddymoney/services/merchant_service.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/screens/admin/admin_merchant_review_screen.dart';

class AdminManageMerchantsScreen extends StatefulWidget {
  const AdminManageMerchantsScreen({super.key});

  @override
  State<AdminManageMerchantsScreen> createState() => _AdminManageMerchantsScreenState();
}

class _AdminManageMerchantsScreenState extends State<AdminManageMerchantsScreen> {
  final _service = MerchantService();
  final _searchCtrl = TextEditingController();

  String _statusFilter = 'all';
  late Future<({List<MerchantModel> merchants, String? error})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  Future<({List<MerchantModel> merchants, String? error})> _load() {
    // NOTE: MerchantService already handles errors and returns friendly tuples.
    // For admins, RLS should allow selecting all merchants.
    return _service.listMerchantsResult(limit: 200);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CaddyMoneyTopAppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: AppSpacing.paddingLg,
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage merchants',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Tap a merchant to view details.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SearchField(controller: _searchCtrl),
                      const SizedBox(height: AppSpacing.md),
                      _StatusFilterChips(
                        value: _statusFilter,
                        onChanged: (v) => setState(() => _statusFilter = v),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                ),
              ),
              FutureBuilder<({List<MerchantModel> merchants, String? error})>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return SliverPadding(
                      padding: AppSpacing.paddingLg,
                      sliver: SliverList.separated(
                        itemCount: 6,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) => const _MerchantTile.loading(),
                      ),
                    );
                  }

                  if (snap.hasError) {
                    return SliverPadding(
                      padding: AppSpacing.paddingLg,
                      sliver: SliverToBoxAdapter(
                        child: _ErrorCard(message: 'Failed to load merchants. Pull to refresh.'),
                      ),
                    );
                  }

                  final data = snap.data;
                  final error = data?.error;
                  final items = _applyFilters(data?.merchants ?? const <MerchantModel>[]);
                  if (error != null) {
                    return SliverPadding(
                      padding: AppSpacing.paddingLg,
                      sliver: SliverToBoxAdapter(
                        child: _ErrorCard(message: error),
                      ),
                    );
                  }

                  if (items.isEmpty) {
                    return SliverPadding(
                      padding: AppSpacing.paddingLg,
                      sliver: SliverToBoxAdapter(
                        child: _EmptyState(statusFilter: _statusFilter, query: _searchCtrl.text),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: AppSpacing.paddingLg,
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final m = items[i];
                        return _MerchantTile(
                          merchant: m,
                          onTap: () {
                            () async {
                              await context.push(
                                AppRoutes.adminMerchantReview,
                                // We still open non-pending merchants in a details-only *decision* mode
                                // (no approve/reject bar), but categories should remain editable.
                                extra: AdminMerchantReviewArgs(merchant: m),
                              );
                              if (mounted) _refresh();
                            }();
                          },
                        );
                      },
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
            ],
          ),
        ),
      ),
    );
  }

  List<MerchantModel> _applyFilters(List<MerchantModel> input) {
    final q = _searchCtrl.text.trim().toLowerCase();

    Iterable<MerchantModel> out = input;
    if (_statusFilter != 'all') {
      out = out.where((m) => m.status.toJson() == _statusFilter);
    }
    if (q.isNotEmpty) {
      bool matches(MerchantModel m) {
        final bn = m.businessName.toLowerCase();
        final email = m.businessEmail.toLowerCase();
        final uid = m.uniqueMerchantId.toLowerCase();
        final owner = [m.ownerFirstName, m.ownerLastName, m.ownerName].whereType<String>().join(' ').toLowerCase();
        return bn.contains(q) || email.contains(q) || uid.contains(q) || owner.contains(q);
      }

      out = out.where(matches);
    }
    return out.toList();
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by business, owner, email, or ID…',
        prefixIcon: Icon(Icons.search_outlined, color: scheme.onSurfaceVariant),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty;
            if (!hasText) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'Clear',
              icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
              onPressed: () => controller.clear(),
            );
          },
        ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.8), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
      ),
    );
  }
}

class _StatusFilterChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _StatusFilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget chip({required String key, required String label}) {
      final selected = value == key;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onChanged(key),
        labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
        selectedColor: scheme.primaryContainer,
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
        side: BorderSide(color: scheme.outline.withValues(alpha: selected ? 0.0 : 0.25)),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        showCheckmark: false,
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        chip(key: 'all', label: 'All'),
        chip(key: 'pending', label: 'Pending'),
        chip(key: 'approved', label: 'Approved'),
        chip(key: 'rejected', label: 'Rejected'),
        chip(key: 'suspended', label: 'Suspended'),
      ],
    );
  }
}

class _MerchantTile extends StatelessWidget {
  final MerchantModel? merchant;
  final VoidCallback? onTap;
  const _MerchantTile({this.merchant, this.onTap});
  const _MerchantTile.loading({super.key}) : merchant = null, onTap = null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (merchant == null) {
      return Container(
        height: 78,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
        ),
      );
    }

    final m = merchant!;
    final status = m.status.toJson();
    final owner = [m.ownerFirstName, m.ownerLastName].whereType<String>().where((e) => e.trim().isNotEmpty).join(' ');
    final subtitle = owner.isNotEmpty ? owner : (m.businessEmail);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            _StatusDot(status: status),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.businessName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.25),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _StatusPill(status: status),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(context, status);
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _statusColor(context, status);
    final bg = c.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w800, letterSpacing: 0.4),
      ),
    );
  }
}

Color _statusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'approved' => scheme.tertiary,
    'pending' => scheme.primary,
    'rejected' => scheme.error,
    'suspended' => scheme.secondary,
    _ => scheme.onSurfaceVariant,
  };
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String statusFilter;
  final String query;
  const _EmptyState({required this.statusFilter, required this.query});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasQuery = query.trim().isNotEmpty;
    final title = hasQuery ? 'No results' : 'No merchants';
    final subtitle = hasQuery
        ? 'Try a different search term.'
        : statusFilter == 'all'
            ? 'There are no merchants to show right now.'
            : 'No merchants match this status.';

    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Icon(Icons.store_outlined, size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
        ],
      ),
    );
  }
}
