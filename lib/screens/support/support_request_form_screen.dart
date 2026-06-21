import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:go_router/go_router.dart';

import 'package:caddymoney/core/enums/support_requester_type.dart';
import 'package:caddymoney/services/support_request_service.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';

class SupportRequestFormArgs {
  final SupportRequesterType requesterType;
  const SupportRequestFormArgs({required this.requesterType});
}

/// A reusable support request form pane.
///
/// Used by both the standalone [SupportRequestFormScreen] route and the
/// tabbed Support Center.
class SupportRequestFormPane extends StatefulWidget {
  final SupportRequesterType requesterType;
  final VoidCallback? onSubmitted;
  final bool autoPopOnSubmit;

  const SupportRequestFormPane({super.key, required this.requesterType, this.onSubmitted, this.autoPopOnSubmit = true});

  @override
  State<SupportRequestFormPane> createState() => _SupportRequestFormPaneState();
}

class _SupportRequestFormPaneState extends State<SupportRequestFormPane> {
  final _service = SupportRequestService();
  final _subjectController = TextEditingController();
  final _descController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final subject = _subjectController.text.trim();
    final desc = _descController.text.trim();

    if (subject.isEmpty || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in subject and description.')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final res = await _service.createSupportRequest(
        requesterType: widget.requesterType,
        subject: subject,
        description: desc,
      );

      if (!mounted) return;
      if (res.request == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Failed to submit request.')));
        return;
      }

      final ticket = res.request!.ticketNumber;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Support request submitted. Ticket: $ticket')));

      widget.onSubmitted?.call();
      if (!widget.autoPopOnSubmit) return;

      // Soft exit after a brief delay so the snackbar is noticeable.
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      context.pop();
    } catch (e) {
      debugPrint('SupportRequestFormPane submit failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to submit request. Please try again.')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final requesterLabel = widget.requesterType.displayName;

    return SingleChildScrollView(
      padding: AppSpacing.paddingLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: AppSpacing.paddingMd,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: cs.outline),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.support_agent, color: cs.onPrimary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Support Request', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Submitted as: $requesterLabel',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Subject', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _subjectController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'E.g. Payment failed / Account issue',
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: cs.outline)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: cs.outline)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: cs.primary, width: 1.4)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Problem description', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _descController,
            minLines: 6,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: 'Tell us what happened, what you expected, and any details that can help.',
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: cs.outline)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: cs.outline)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: cs.primary, width: 1.4)),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.onPrimary),
                    )
                  : Icon(Icons.send, color: cs.onPrimary),
              label: Text(
                _isSubmitting ? 'Submitting…' : 'Submit',
                style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'We’ll respond as soon as possible. Keep your ticket number for reference.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class SupportRequestFormScreen extends StatefulWidget {
  final SupportRequestFormArgs args;
  const SupportRequestFormScreen({super.key, required this.args});

  @override
  State<SupportRequestFormScreen> createState() => _SupportRequestFormScreenState();
}

class _SupportRequestFormScreenState extends State<SupportRequestFormScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CaddyMoneyTopAppBar(),
      body: SafeArea(
        child: SupportRequestFormPane(requesterType: widget.args.requesterType),
      ),
    );
  }
}
