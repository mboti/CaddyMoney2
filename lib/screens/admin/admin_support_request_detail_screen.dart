import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:caddymoney/core/enums/support_request_status.dart';
import 'package:caddymoney/models/support_request_model.dart';
import 'package:caddymoney/services/support_request_service.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';
import 'package:caddymoney/widgets/admin_support_notifications_app_bar.dart';

class AdminSupportRequestDetailScreen extends StatefulWidget {
  final String requestId;
  const AdminSupportRequestDetailScreen({super.key, required this.requestId});

  @override
  State<AdminSupportRequestDetailScreen> createState() => _AdminSupportRequestDetailScreenState();
}

class _AdminSupportRequestDetailScreenState extends State<AdminSupportRequestDetailScreen> {
  final _service = SupportRequestService();
  late Future<({SupportRequestModel? request, String? error})> _future;
  bool _isUpdating = false;
  late final TextEditingController _responseController;
  bool _isSendingResponse = false;

  @override
  void initState() {
    super.initState();
    _future = _service.getRequestById(widget.requestId);
    _responseController = TextEditingController();
  }

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  String _requesterLabel(SupportRequestModel r) {
    final name = (r.requesterDisplayName ?? '').trim();
    return name.isEmpty ? r.requesterType.displayName : '${r.requesterType.displayName} ($name)';
  }

  Future<void> _refresh() async {
    // setState callbacks must be synchronous (return void), otherwise Flutter
    // throws: "setState() callback argument returned a Future".
    setState(() {
      _future = _service.getRequestById(widget.requestId);
    });
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _setStatus(SupportRequestModel current, SupportRequestStatus next) async {
    if (_isUpdating) return;
    if (current.status == next) return;
    setState(() => _isUpdating = true);
    try {
      final res = await _service.updateStatus(requestId: current.id, status: next);
      if (!mounted) return;
      if (res.request == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Failed to update status.')));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated to “${res.request!.status.displayName}”.')),
      );
      setState(() {
        _future = Future.value((request: res.request, error: null));
      });
    } catch (e) {
      debugPrint('AdminSupportRequestDetailScreen updateStatus failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update status.')));
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _sendResponse(SupportRequestModel current) async {
    if (_isSendingResponse) return;
    final text = _responseController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please write a response first.')));
      return;
    }

    setState(() => _isSendingResponse = true);
    try {
      final res = await _service.respondToRequest(requestId: current.id, response: text);
      if (!mounted) return;
      if (res.request == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Failed to send response.')));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Response sent for ${res.request!.ticketNumber}.')),
      );
      setState(() {
        _future = Future.value((request: res.request, error: null));
      });
    } catch (e) {
      debugPrint('AdminSupportRequestDetailScreen respond failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send response.')));
    } finally {
      if (mounted) setState(() => _isSendingResponse = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('MMM d, yyyy • HH:mm');

    return Scaffold(
      appBar: const AdminSupportNotificationsAppBar(showLeading: true),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<({SupportRequestModel? request, String? error})>(
            future: _future,
            builder: (context, snap) {
              final waiting = snap.connectionState == ConnectionState.waiting;
              if (waiting) return const Center(child: CircularProgressIndicator());

              final err = snap.data?.error;
              final r = snap.data?.request;
              if (snap.hasError || r == null) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppSpacing.paddingLg,
                  children: [
                    Text(err ?? 'Support request not found. Pull to refresh.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                );
              }

              // Keep controller in sync when loading an existing response.
              // Only auto-fill if the admin hasn't started typing.
              if (_responseController.text.trim().isEmpty && (r.adminResponse ?? '').trim().isNotEmpty) {
                _responseController.text = r.adminResponse!.trim();
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
                    '${_requesterLabel(r)} • ${fmt.format(r.createdAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Subject', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(text: r.subject),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Description', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(text: r.description),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Admin response', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: AppSpacing.paddingMd,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: cs.outline),
                      color: cs.surface,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _responseController,
                          minLines: 3,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Write a response to the requester…',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: _isSendingResponse ? 0.8 : 1,
                          child: FilledButton.icon(
                            onPressed: _isSendingResponse ? null : () => _sendResponse(r),
                            icon: _isSendingResponse
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.onPrimary),
                                  )
                                : const Icon(Icons.send_rounded),
                            label: Text(_isSendingResponse ? 'Sending…' : 'Send response'),
                          ),
                        ),
                        if (r.respondedAt != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Last sent: ${fmt.format(r.respondedAt!.toLocal())}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Status', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: AppSpacing.paddingMd,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: cs.outline),
                      color: cs.surface,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.tune, color: cs.primary),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<SupportRequestStatus>(
                              value: r.status,
                              isExpanded: true,
                              items: SupportRequestStatus.values
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s.displayName)))
                                  .toList(),
                              onChanged: _isUpdating ? null : (v) {
                                if (v != null) _setStatus(r, v);
                              },
                            ),
                          ),
                        ),
                        if (_isUpdating) ...[
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.primary)),
                        ],
                      ],
                    ),
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
