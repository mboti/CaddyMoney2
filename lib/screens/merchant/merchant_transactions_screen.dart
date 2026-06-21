import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:caddymoney/models/transaction_model.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/core/theme/date_range_picker_theme.dart';
import 'package:caddymoney/screens/merchant/widgets/merchant_bottom_nav_bar.dart';
import 'package:caddymoney/screens/merchant/widgets/merchant_totals_row.dart';
import 'package:caddymoney/screens/merchant/widgets/payment_list_item.dart';
import 'package:caddymoney/services/transaction_service.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/support_notifications_app_bar.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';
import 'package:caddymoney/widgets/transactions_date_range_bar.dart';

class MerchantTransactionsScreen extends StatefulWidget {
  const MerchantTransactionsScreen({super.key});

  @override
  State<MerchantTransactionsScreen> createState() => _MerchantTransactionsScreenState();
}

class _MerchantTransactionsScreenState extends State<MerchantTransactionsScreen> {
  final _transactionService = TransactionService();
  String? _merchantId;
  late Future<List<TransactionModel>> _txnsFuture;
  late DateTimeRange _dateRange;

  @override
  void initState() {
    super.initState();
    _dateRange = _todayRange();
    _txnsFuture = Future.value(const <TransactionModel>[]);
  }

  static DateTimeRange _todayRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return DateTimeRange(start: start, end: end);
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

    final start = DateTime(picked.start.year, picked.start.month, picked.start.day);
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
    setState(() => _dateRange = DateTimeRange(start: start, end: end));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authProvider = context.read<AuthProvider>();
    final newMerchantId = authProvider.currentMerchant?.id;
    if (newMerchantId != _merchantId) {
      _merchantId = newMerchantId;
      _reload();
    }
  }

  void _reload() {
    final id = _merchantId;
    setState(() {
      _txnsFuture = id == null ? Future.value(const <TransactionModel>[]) : _transactionService.listMerchantTransactions(merchantId: id, limit: 50, completedOnly: true);
    });
  }

  String _formatTxnDate(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final label = date == today
        ? 'Today'
        : date == today.subtract(const Duration(days: 1))
            ? 'Yesterday'
            : DateFormat.yMMMd().format(local);
    return '$label, ${DateFormat.Hm().format(local)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final listBottomPadding = bottomInset + 96.0;
    return Scaffold(
      extendBody: true,
      appBar: const SupportNotificationsAppBar(showLeading: false, requesterType: SupportRequesterType.merchant),
      bottomNavigationBar: const MerchantBottomNavBar(),
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<TransactionModel>>(
          future: _txnsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              debugPrint('MerchantTransactionsScreen: failed to load: ${snapshot.error}');
            }

            final isLoading = snapshot.connectionState == ConnectionState.waiting;
            final txns = snapshot.data ?? const <TransactionModel>[];
            final filtered = txns.where((t) => _isInSelectedRange(t.completedAt ?? t.createdAt)).toList(growable: false);
            final filteredTotalReceived = filtered.fold<double>(0, (sum, t) => sum + t.amount);
            final currencyCode = (filtered.isNotEmpty ? filtered.first.currencyCode : (txns.isNotEmpty ? txns.first.currencyCode : null)) ?? 'EUR';

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Transactions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: AppSpacing.paddingLg,
                  child: MerchantTotalsRow(
                    totalReceived: filteredTotalReceived,
                    transactionCount: filtered.length,
                    currencyCode: currencyCode,
                    isLoading: isLoading,
                  ),
                ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                      child: TransactionsDateRangeBar(
                        range: _dateRange,
                        onRangeChanged: (r) => setState(() => _dateRange = r),
                        onOpenFilter: _pickDateRange,
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: cs.primary,
                        onRefresh: () async => _reload(),
                        child: isLoading
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, listBottomPadding),
                                children: [
                                  const SizedBox(height: AppSpacing.xl),
                                  Center(child: CircularProgressIndicator(color: cs.primary)),
                                ],
                              )
                            : txns.isEmpty
                                ? ListView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, listBottomPadding),
                                    children: [
                                      const SizedBox(height: AppSpacing.sm),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(AppSpacing.lg),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(AppRadius.lg),
                                          border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(child: Text('No payments yet.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : filtered.isEmpty
                                    ? ListView(
                                        physics: const AlwaysScrollableScrollPhysics(),
                                        padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, listBottomPadding),
                                        children: [
                                          const SizedBox(height: AppSpacing.sm),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(AppSpacing.lg),
                                            decoration: BoxDecoration(
                                              color: cs.surfaceContainerHighest.withValues(alpha: 0.14),
                                              borderRadius: BorderRadius.circular(AppRadius.lg),
                                              border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
                                            ),
                                            child: Text(
                                              'No payments in this date range.',
                                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                                            ),
                                          ),
                                        ],
                                      )
                                    : ListView.separated(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, listBottomPadding),
                                      itemCount: filtered.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                                    itemBuilder: (context, index) {
                                        final t = filtered[index];
                                      return PaymentListItem(
                                        amount: t.amount,
                                        date: _formatTxnDate(t.completedAt ?? t.createdAt),
                                        paymentId: t.transactionReference,
                                        currencyCode: t.currencyCode,
                                      );
                                    },
                                  ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
