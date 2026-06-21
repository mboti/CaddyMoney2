import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/models/payment_intent_model.dart';
import 'package:caddymoney/models/coupon_model.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/screens/user/widgets/user_bottom_nav_bar.dart';
import 'package:caddymoney/services/coupon_service.dart';
import 'package:caddymoney/services/payment_intent_service.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class QrPaymentConfirmationScreen extends StatefulWidget {
  final String tokenOrId;

  const QrPaymentConfirmationScreen({super.key, required this.tokenOrId});

  @override
  State<QrPaymentConfirmationScreen> createState() => _QrPaymentConfirmationScreenState();
}

class _QrPaymentConfirmationScreenState extends State<QrPaymentConfirmationScreen> {
  final _service = PaymentIntentService();
  final _couponService = CouponService();

  bool _isLoading = true;
  bool _isPaying = false;
  String? _error;
  PaymentIntentModel? _intent;
  String? _merchantName;
  List<String> _merchantCategories = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _isPaying = false;
      _error = null;
      _intent = null;
      _merchantName = null;
      _merchantCategories = const [];
    });

    try {
      final res = await _service.resolvePaymentIntent(tokenOrId: widget.tokenOrId);
      if (!mounted) return;
      if (res.intent == null) {
        setState(() {
          _error = res.error ?? 'Request failed.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _intent = res.intent;
        _merchantName = res.merchantName;
        _merchantCategories = res.merchantCategories;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('QrPaymentConfirmationScreen._load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    final intent = _intent;
    final status = (intent?.status ?? '').toLowerCase();
    final isExpired = status == 'expired' || (intent?.isExpired ?? false);
    final isPaid = status == 'paid' || status == 'completed' || status == 'succeeded';
    final isPending = status.isEmpty || status == 'pending';

    String? banner;
    Color bannerColor = cs.surfaceContainerHighest;
    Color bannerText = cs.onSurface;
    if (isExpired) {
      banner = l10n?.paymentExpired ?? 'This payment request has expired';
      bannerColor = cs.errorContainer;
      bannerText = cs.onErrorContainer;
    } else if (isPaid) {
      banner = l10n?.paymentAlreadyPaid ?? 'Payment completed successfully';
      bannerColor = cs.tertiaryContainer;
      bannerText = cs.onTertiaryContainer;
    }

    return Scaffold(
      // Keep the bottom action buttons above the persistent bottom navigation.
      extendBody: false,
      appBar: const CaddyMoneyTopAppBar(),
      bottomNavigationBar: const UserBottomNavBar(),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: Text(
                  l10n?.confirmPayment ?? 'Confirm payment',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _ErrorPanel(message: _error!, onRetry: _load)
                          : intent == null
                              ? _ErrorPanel(message: l10n?.paymentNotFound ?? 'Payment request not found', onRetry: _load)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                              if (banner != null)
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: bannerColor,
                                    borderRadius: BorderRadius.circular(AppRadius.lg),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(isExpired ? Icons.timer_off_outlined : Icons.verified_outlined, color: bannerText),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(child: Text(banner, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: bannerText, height: 1.35))),
                                    ],
                                  ),
                                ),
                              if (banner != null) const SizedBox(height: AppSpacing.md),
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withValues(alpha: 0.20),
                                  borderRadius: BorderRadius.circular(AppRadius.xl),
                                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _merchantName?.trim().isNotEmpty == true ? _merchantName! : '—',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (_merchantCategories.isNotEmpty) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        _merchantCategories.join(', '),
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      _formatAmount(intent.amount, intent.currencyCode),
                                      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, height: 1.0),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    _InfoRow(label: l10n?.status ?? 'Status', value: status.isEmpty ? 'pending' : status),
                                    const SizedBox(height: AppSpacing.xs),
                                    _InfoRow(label: l10n?.currency ?? 'Currency', value: intent.currencyCode),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              FilledButton(
                                onPressed: (!isPending || isExpired || isPaid)
                                    ? null
                                    : (_isPaying ? null : () => _onPayNowPressed(intent)),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: _isPaying
                                      ? SizedBox(
                                          key: ValueKey('loading'),
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.onPrimary),
                                        )
                                      : const Text('Pay Now'),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              OutlinedButton(
                                onPressed: () => context.pop(),
                                child: Text(l10n?.backToScanner ?? 'Back to scanner'),
                              ),
                                  ],
                                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onPayNowPressed(PaymentIntentModel intent) async {
    if (_isPaying) return;

    final categories = _merchantCategories;
    if (categories.isEmpty) {
      _showError('No merchant category found for coupon matching.');
      return;
    }

    setState(() => _isPaying = true);
    try {
      final coupons = await _couponService.listEligibleCoupons(
        merchantCategories: categories,
        currencyCode: intent.currencyCode,
      );
      if (!mounted) return;

      if (coupons.isEmpty) {
        _showError(
          'No eligible coupons available for this merchant. '
          'Make sure you have an active coupon matching the merchant category.',
        );
        return;
      }

      final selected = await showModalBottomSheet<CouponModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => CouponPickerSheet(
          coupons: coupons,
          merchantName: _merchantName ?? 'Merchant',
          amount: intent.amount,
          currencyCode: intent.currencyCode,
        ),
      );
      if (!mounted || selected == null) return;

      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => PaymentConfirmSheet(
          merchantName: _merchantName ?? 'Merchant',
          coupon: selected,
          payAmount: intent.amount,
          currencyCode: intent.currencyCode,
        ),
      );
      if (!mounted || confirmed != true) return;

      final res = await _service.confirmPaymentWithCoupon(
        paymentIntentId: intent.id,
        couponId: selected.id,
      );
      if (!mounted) return;

      if (!res.success) {
        _showError(res.error ?? 'Payment failed.');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.alreadyPaid ? 'This QR was already paid.' : 'Payment successful.')),
      );
      await _load();

      // The DB write can be slightly asynchronous; give it a brief moment so the
      // Home totals query is very likely to include the new transaction.
      await Future.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;

      // Return a "success" result so QrScanScreen (and then Home) can refresh.
      context.pop(true);
    } catch (e) {
      debugPrint('QrPaymentConfirmationScreen._onPayNowPressed failed: $e');
      if (!mounted) return;
      _showError('Payment failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatAmount(double amount, String currencyCode) {
    final s = amount.toStringAsFixed(2);
    return '$s $currencyCode';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
        const SizedBox(width: AppSpacing.md),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Bottom sheet that lets the user pick an eligible coupon.
class CouponPickerSheet extends StatelessWidget {
  final List<CouponModel> coupons;
  final String merchantName;
  final double amount;
  final String currencyCode;

  const CouponPickerSheet({
    super.key,
    required this.coupons,
    required this.merchantName,
    required this.amount,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
        ),
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose a coupon',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$merchantName • ${amount.toStringAsFixed(2)} $currencyCode',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: coupons.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final c = coupons[i];
                      final canCover = c.balance >= amount;
                      return InkWell(
                        onTap: () => context.pop(c),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(Icons.local_offer_outlined, color: cs.primary),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.title,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      c.category,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${c.balance.toStringAsFixed(2)} $currencyCode',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    canCover ? 'Covers full amount' : 'Partial coverage',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: canCover ? cs.tertiary : cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Final validation happens on the server.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that asks for final confirmation before calling the backend.
class PaymentConfirmSheet extends StatefulWidget {
  final String merchantName;
  final CouponModel coupon;
  final double payAmount;
  final String currencyCode;

  const PaymentConfirmSheet({
    super.key,
    required this.merchantName,
    required this.coupon,
    required this.payAmount,
    required this.currencyCode,
  });

  @override
  State<PaymentConfirmSheet> createState() => _PaymentConfirmSheetState();
}

class _PaymentConfirmSheetState extends State<PaymentConfirmSheet> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final after = (widget.coupon.balance - widget.payAmount).clamp(0, double.infinity);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
        ),
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Confirm payment', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    children: [
                      _ConfirmRow(label: 'Merchant', value: widget.merchantName),
                      const SizedBox(height: AppSpacing.xs),
                      _ConfirmRow(label: 'Coupon', value: '${widget.coupon.title} • ${widget.coupon.category}'),
                      const SizedBox(height: AppSpacing.xs),
                      _ConfirmRow(label: 'Amount', value: '${widget.payAmount.toStringAsFixed(2)} ${widget.currencyCode}'),
                      const SizedBox(height: AppSpacing.xs),
                      _ConfirmRow(label: 'Coupon after', value: '${after.toStringAsFixed(2)} ${widget.currencyCode}'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _confirming ? null : () => context.pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: _confirming
                            ? null
                            : () async {
                                setState(() => _confirming = true);
                                // Let the caller actually execute the payment; we only confirm intent.
                                if (!mounted) return;
                                context.pop(true);
                              },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: _confirming
                              ? SizedBox(
                                  key: const ValueKey('loading'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.onPrimary),
                                )
                              : const Text('Confirm'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;

  const _ConfirmRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
        const SizedBox(width: AppSpacing.md),
        Flexible(child: Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorPanel({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: cs.onErrorContainer, size: 28),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
