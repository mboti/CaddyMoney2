import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/core/theme/date_range_picker_theme.dart';
import 'package:caddymoney/core/enums/transaction_type.dart';
import 'package:caddymoney/models/transaction_model.dart';
import 'package:caddymoney/services/transaction_service.dart';
import 'package:caddymoney/services/merchant_service.dart';
import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/core/utils/transaction_reference.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/screens/user/widgets/user_bottom_nav_bar.dart';
import 'package:caddymoney/widgets/transactions_date_range_bar.dart';
import 'package:caddymoney/widgets/support_notifications_app_bar.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TransactionService _service = TransactionService();

  bool _loading = true;
  List<TransactionModel> _items = const [];
  // Default to Paid so users land on QR merchant payments first.
  TransactionsDirectionFilter _filter = TransactionsDirectionFilter.paid;
  late DateTimeRange _dateRange;

  @override
  void initState() {
    super.initState();
    // Default to a rolling 30-day window.
    _dateRange = TransactionsDateRangeBar.presetMonth();
    _load();
  }

  bool _isInSelectedRange(DateTime dt) {
    final v = dt.toLocal();
    final s = _dateRange.start.toLocal();
    final e = _dateRange.end.toLocal();
    return (v.isAtSameMomentAs(s) || v.isAfter(s)) && (v.isAtSameMomentAs(e) || v.isBefore(e));
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      helpText: 'Select date range',
      saveText: 'Apply',
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return Theme(data: buildBrandDateRangePickerTheme(context), child: child);
      },
    );
    if (!mounted || picked == null) return;

    // Normalize to full-day coverage so transactions on the end date are included.
    final start = DateTime(picked.start.year, picked.start.month, picked.start.day);
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
    setState(() => _dateRange = DateTimeRange(start: start, end: end));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.listMyTransactions();
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      debugPrint('TransactionsScreen._load failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final uid = SupabaseConfig.auth.currentUser?.id;

    List<TransactionModel> filteredItems() {
      if (uid == null) return _items;
      final inRange = _items.where((t) => _isInSelectedRange(t.createdAt));
      switch (_filter) {
        case TransactionsDirectionFilter.incoming:
          // “Coupon” = coupons you received (incoming user→user).
          return inRange
              .where((t) => t.type == TransactionType.userToUser && t.receiverProfileId == uid)
              .toList(growable: false);
        case TransactionsDirectionFilter.outgoing:
          // “Send” = money transfers you sent to another user (outgoing user→user).
          // IMPORTANT: this must never include merchant payments (including coupon-based spends).
          return inRange
              .where((t) => t.type == TransactionType.userToUser && t.senderProfileId == uid)
              .toList(growable: false);
        case TransactionsDirectionFilter.paid:
          // “Paid” = completed user->merchant payments where I'm the sender.
          return inRange
              .where((t) => t.type == TransactionType.userToMerchant && t.senderProfileId == uid)
              .toList(growable: false);
      }
    }

    final filtered = filteredItems();

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: Text('Transactions', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
        ),
        const SizedBox(height: AppSpacing.lg),
        TransactionsDateRangeBar(
          range: _dateRange,
          onRangeChanged: (r) => setState(() => _dateRange = r),
          onOpenFilter: _pickDateRange,
        ),
        // Subtle extra breathing room between the date-range card and the main panel.
        const SizedBox(height: AppSpacing.md + AppSpacing.xs),
      ],
    );

    return Scaffold(
      appBar: const SupportNotificationsAppBar(showLeading: false, requesterType: SupportRequesterType.user),
      bottomNavigationBar: const UserBottomNavBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: ListView(
                    padding: AppSpacing.paddingLg,
                    children: [
                      header,
                      TransactionsPanel(
                        filterValue: _filter,
                        onFilterChanged: (v) => setState(() => _filter = v),
                        allItemsEmpty: _items.isEmpty,
                        filtered: filtered,
                        currentUserId: uid,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

enum TransactionsDirectionFilter { incoming, outgoing, paid }

class TransactionsDirectionFilterBar extends StatelessWidget {
  final TransactionsDirectionFilter value;
  final ValueChanged<TransactionsDirectionFilter> onChanged;

  const TransactionsDirectionFilterBar({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final dividerColor = cs.outlineVariant.withValues(alpha: 0.20);

    BorderRadius tabRadius({required bool selected, required bool isFirst, required bool isLast}) {
      if (!selected) return BorderRadius.zero;
      // Rounded only on the top so the active tab feels “attached” to the content below.
      final inner = Radius.circular(AppRadius.lg);
      final outer = Radius.circular(AppRadius.xl);
      return BorderRadius.only(
        topLeft: isFirst ? outer : inner,
        topRight: isLast ? outer : inner,
      );
    }

    Widget seg({required int index, required TransactionsDirectionFilter v, required String label}) {
      final selected = v == value;
      final fg = selected ? cs.onPrimary : cs.onSurface;

      // A flatter, fintech-style header tab: no pill, minimal borders.
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected ? null : cs.surface,
              gradient: selected
                  ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.transactionFilterSelectedGradient)
                  : null,
              borderRadius: tabRadius(selected: selected, isFirst: index == 0, isLast: index == 2),
              border: Border(
                bottom: BorderSide(color: selected ? Colors.transparent : dividerColor, width: 1),
              ),
            ),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w900, color: fg) ?? TextStyle(fontWeight: FontWeight.w900, color: fg),
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            seg(index: 0, v: TransactionsDirectionFilter.paid, label: 'Paid'),
            seg(index: 1, v: TransactionsDirectionFilter.incoming, label: 'Coupon'),
            seg(index: 2, v: TransactionsDirectionFilter.outgoing, label: 'Send'),
          ],
        ),
        // The main divider is handled by the tabs themselves; this ensures the border line
        // continues seamlessly under the selected tab without adding extra visual weight.
        // (The content area will start immediately after this header.)
      ],
    );
  }
}

class TransactionsPanel extends StatelessWidget {
  final TransactionsDirectionFilter filterValue;
  final ValueChanged<TransactionsDirectionFilter> onFilterChanged;
  final bool allItemsEmpty;
  final List<TransactionModel> filtered;
  final String? currentUserId;

  const TransactionsPanel({
    super.key,
    required this.filterValue,
    required this.onFilterChanged,
    required this.allItemsEmpty,
    required this.filtered,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget emptyState({required IconData icon, required String title, required String message}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
        child: Column(
          children: [
            Icon(icon, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: tt.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final panelBorder = cs.outlineVariant.withValues(alpha: 0.26);
    final dividerColor = cs.outlineVariant.withValues(alpha: 0.20);

    Widget panelDivider({double left = 0, double right = 0}) => Padding(
          padding: EdgeInsets.only(left: left, right: right),
          child: Divider(height: 1, thickness: 1, color: dividerColor),
        );

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: panelBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Integrated card-header navigation (no pill container).
            TransactionsDirectionFilterBar(value: filterValue, onChanged: onFilterChanged),
            if (allItemsEmpty)
              emptyState(
                icon: Icons.receipt_long,
                title: 'No transactions yet',
                message: 'When you send or receive money, it will appear here for both accounts.',
              )
            else if (filtered.isEmpty)
              emptyState(
                icon: Icons.filter_list_off,
                title: 'No transactions for this filter',
                message: 'Try switching to “Paid”, “Coupon”, or “Send” to see transactions.',
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < filtered.length; i++) ...[
                    TransactionListRow(
                      transaction: filtered[i],
                      isCredit: currentUserId != null && filtered[i].receiverProfileId == currentUserId,
                    ),
                    if (i != filtered.length - 1)
                      // Inset divider so it aligns with the row content (not under the colored strip).
                      panelDivider(left: AppSpacing.md + 3 + AppSpacing.md + 40 + AppSpacing.md, right: AppSpacing.md),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class TransactionListRow extends StatelessWidget {
  final TransactionModel transaction;
  final bool isCredit;

  const TransactionListRow({super.key, required this.transaction, required this.isCredit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final amountColor = isCredit ? AppColors.transactionReceived : AppColors.transactionSent;
    final category = TransactionListTile._transferCategory(transaction);
    final date = TransactionListTile._formatTime(transaction.createdAt);
    final reference = transaction.transactionReference.trim();
    final counterparty = TransactionListTile._counterpartyNameFor(transaction, isCredit: isCredit);
    final isMerchantPayment = transaction.type == TransactionType.userToMerchant;

    final referenceStyle = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final baseCategoryStyle = tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface);
    final categoryStyle = baseCategoryStyle?.copyWith(fontSize: (baseCategoryStyle.fontSize ?? 16) + 2);

    final accent = AppColors.couponColorForCategory((category ?? '').isNotEmpty ? category! : (isMerchantPayment ? 'services' : 'tech'));
    final icon = AppColors.couponIconForCategory(category ?? '');

    return Padding(
      // Tighter vertical rhythm for a more compact, premium list.
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 40,
            margin: const EdgeInsets.only(right: AppSpacing.md, top: 2),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(999)),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Center(child: Icon(icon, size: 19, color: accent)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: isMerchantPayment
                          ? _MerchantPrimaryLine(
                              transaction: transaction,
                              joinedMerchantName: counterparty,
                              category: category,
                              categoryStyle: categoryStyle,
                            )
                          : _UserPrimaryLine(
                              category: category,
                              personCounterpartyName: counterparty,
                              categoryStyle: categoryStyle,
                              referenceStyle: referenceStyle,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${isCredit ? '+' : '-'}${transaction.amount.abs().toStringAsFixed(2)}€',
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: amountColor),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      if (reference.isNotEmpty) TextSpan(text: shortenTransactionReference(reference), style: referenceStyle),
                      if (reference.isNotEmpty) TextSpan(text: '  •  ', style: referenceStyle),
                      TextSpan(text: date, style: referenceStyle),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isCredit && TransactionListTile._paymentSummary(transaction) != null) ...[
                  const SizedBox(height: 10),
                  _PaymentPill(text: TransactionListTile._paymentSummary(transaction)!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionListTile extends StatelessWidget {
  final TransactionModel transaction;
  final bool isCredit;

  const TransactionListTile({super.key, required this.transaction, required this.isCredit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final amountColor = isCredit ? AppColors.transactionReceived : AppColors.transactionSent;
    final category = _transferCategory(transaction);
    final date = _formatTime(transaction.createdAt);
    final reference = transaction.transactionReference.trim();
    final counterparty = _counterpartyNameFor(transaction, isCredit: isCredit);
    final isMerchantPayment = transaction.type == TransactionType.userToMerchant;

    final referenceStyle = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final baseCategoryStyle = tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface);
    final categoryStyle = baseCategoryStyle?.copyWith(fontSize: (baseCategoryStyle.fontSize ?? 16) + 2);

    final accent = AppColors.couponColorForCategory((category ?? '').isNotEmpty ? category! : (isMerchantPayment ? 'services' : 'tech'));
    final icon = _iconForCategory(category ?? '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 44,
            margin: const EdgeInsets.only(right: AppSpacing.md, top: 2),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(999)),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Center(child: Icon(icon, size: 20, color: accent)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: isMerchantPayment
                          ? _MerchantPrimaryLine(
                              transaction: transaction,
                              joinedMerchantName: counterparty,
                              category: category,
                              categoryStyle: categoryStyle,
                            )
                          : _UserPrimaryLine(
                              category: category,
                              personCounterpartyName: counterparty,
                              categoryStyle: categoryStyle,
                              referenceStyle: referenceStyle,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${isCredit ? '+' : '-'}${transaction.amount.abs().toStringAsFixed(2)}€',
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: amountColor),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      if (reference.isNotEmpty) TextSpan(text: shortenTransactionReference(reference), style: referenceStyle),
                      if (reference.isNotEmpty) TextSpan(text: '  •  ', style: referenceStyle),
                      TextSpan(text: date, style: referenceStyle),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isCredit && _paymentSummary(transaction) != null) ...[
                  const SizedBox(height: 10),
                  _PaymentPill(text: _paymentSummary(transaction)!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconForCategory(String category) {
    // Delegate to the shared mapping used by the Home screen.
    return AppColors.couponIconForCategory(category);
  }

  static String _primaryLineFor(TransactionModel t) {
    final category = _transferCategory(t);
    if (category != null && category.isNotEmpty) return category;
    return _fallbackTitleFor(t);
  }

  static String _counterpartyNameFor(TransactionModel t, {required bool isCredit}) {
    switch (t.type) {
      case TransactionType.userToUser:
        if (isCredit) return (t.senderFullName ?? '').trim();
        return (t.receiverFullName ?? '').trim();
      case TransactionType.userToMerchant:
        return (t.receiverMerchantBusinessName ?? '').trim();
      case TransactionType.refund:
        return '';
      case TransactionType.adjustment:
        return '';
    }
  }

  static String _fallbackTitleFor(TransactionModel t) {
    switch (t.type) {
      case TransactionType.userToUser:
        return 'Transfer';
      case TransactionType.userToMerchant:
        return 'Spend';
      case TransactionType.refund:
        return 'Refund';
      case TransactionType.adjustment:
        return 'Adjustment';
    }
  }

  static String? _transferCategory(TransactionModel t) {
    final m = t.metadata;
    if (m == null) return null;
    final v = m['category'];
    final s = v?.toString();
    if (s == null || s.trim().isEmpty) return null;
    return s.trim();
  }

  static String _formatTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  static String? _paymentSummary(TransactionModel t) {
    final m = t.metadata;
    if (m == null) return null;
    final pm = m['payment_method'];
    if (pm is! Map) return null;
    final brand = pm['brand']?.toString();
    final last4 = pm['last4']?.toString();
    if (brand == null || last4 == null) return null;
    return '${brand.toUpperCase()} •••• $last4';
  }
}

class _MerchantPrimaryLine extends StatelessWidget {
  final TransactionModel transaction;
  final String joinedMerchantName;
  final String? category;
  final TextStyle? categoryStyle;

  const _MerchantPrimaryLine({
    required this.transaction,
    required this.joinedMerchantName,
    required this.category,
    required this.categoryStyle,
  });

  static final Set<String> _debugPrintedTxIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final cat = category?.trim() ?? '';
    final joined = joinedMerchantName.trim();
    final merchantId = transaction.merchantLookupId?.trim() ?? '';

    if (kDebugMode && _debugPrintedTxIds.length < 10 && _debugPrintedTxIds.add(transaction.id)) {
      debugPrint(
        'Paid tile tx=${transaction.id} joinedMerchant="$joined" merchantLookupId="$merchantId" '
        'receiver_merchant_id="${transaction.receiverMerchantId}" meta=${transaction.metadata}',
      );
    }

    // If join already provided the business name, use it.
    if (joined.isNotEmpty) {
      return _MerchantAndCategoryText(merchant: joined, category: cat, style: categoryStyle);
    }

    // Otherwise, try a fallback lookup by merchant id.
    if (merchantId.isEmpty) {
      // Last fallback: show category only.
      if (cat.isEmpty) return const SizedBox.shrink();
      return Text(cat, style: categoryStyle, overflow: TextOverflow.ellipsis);
    }

    return FutureBuilder<String?>(
      future: MerchantService().getBusinessNameByMerchantId(merchantId),
      builder: (context, snap) {
        final name = (snap.data ?? '').trim();
        if (name.isEmpty) {
          // While loading or if unavailable, keep the UI stable: show category only.
          if (cat.isEmpty) return const SizedBox.shrink();
          return Text(cat, style: categoryStyle, overflow: TextOverflow.ellipsis);
        }
        return _MerchantAndCategoryText(merchant: name, category: cat, style: categoryStyle);
      },
    );
  }
}

class _MerchantAndCategoryText extends StatelessWidget {
  final String merchant;
  final String category;
  final TextStyle? style;

  const _MerchantAndCategoryText({required this.merchant, required this.category, required this.style});

  @override
  Widget build(BuildContext context) {
    if (merchant.isEmpty && category.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(
        children: [
          if (merchant.isNotEmpty) TextSpan(text: merchant, style: style),
          // Match the dot separator used in the metadata line.
          if (merchant.isNotEmpty && category.isNotEmpty) TextSpan(text: '  •  ', style: style),
          if (category.isNotEmpty) TextSpan(text: category, style: style),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _UserPrimaryLine extends StatelessWidget {
  final String? category;
  final String personCounterpartyName;
  final TextStyle? categoryStyle;
  final TextStyle? referenceStyle;

  const _UserPrimaryLine({
    required this.category,
    required this.personCounterpartyName,
    required this.categoryStyle,
    required this.referenceStyle,
  });

  @override
  Widget build(BuildContext context) {
    final cat = category?.trim() ?? '';
    final person = personCounterpartyName.trim();

    if (cat.isNotEmpty) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: cat, style: categoryStyle),
            if (person.isNotEmpty) ...[
              TextSpan(text: '  ', style: categoryStyle),
              TextSpan(text: '[${person}]', style: referenceStyle?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    if (person.isNotEmpty) return Text('[${person}]', style: categoryStyle, overflow: TextOverflow.ellipsis);
    return const SizedBox.shrink();
  }
}

class _PaymentPill extends StatelessWidget {
  final String text;
  const _PaymentPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.credit_card, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
