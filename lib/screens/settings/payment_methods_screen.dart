import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:caddymoney/models/payment_method_model.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/services/payment_method_service.dart';
import 'package:caddymoney/core/enums/app_role.dart';
import 'package:caddymoney/screens/user/widgets/user_bottom_nav_bar.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final PaymentMethodService _service = PaymentMethodService();

  bool _loading = true;
  bool _saving = false;
  List<PaymentMethodModel> _methods = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.listMyPaymentMethods();
      if (!mounted) return;
      setState(() => _methods = list);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _showMessage(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _showAddCardSheet() async {
    final res = await showModalBottomSheet<_AddCardSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => const _AddCardSheet(),
    );

    if (res == null) return;
    if (_saving) return;

    setState(() => _saving = true);
    try {
      final added = await _service.addCard(
        cardNumber: res.cardNumber,
        expMonth: res.expMonth,
        expYear: res.expYear,
        holderName: res.holderName,
        nickname: res.nickname,
        makeDefault: res.makeDefault,
      );
      if (!mounted) return;
      _showMessage(added.message ?? (added.success ? 'Card saved.' : 'Failed to save card'));
      if (added.success) await _load();
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _setDefault(PaymentMethodModel m) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ok = await _service.setDefault(m.id);
      if (!mounted) return;
      _showMessage(ok ? 'Default card updated.' : 'Failed to update default card');
      if (ok) await _load();
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _delete(PaymentMethodModel m) async {
    final cs = Theme.of(context).colorScheme;
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (context) => Padding(
        padding: AppSpacing.paddingLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remove card', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text('This will remove •••• ${m.last4} from your account.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => context.pop(false), child: const Text('Cancel'))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                    onPressed: () => context.pop(true),
                    child: const Text('Remove'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;
    if (_saving) return;

    setState(() => _saving = true);
    try {
      final ok = await _service.deletePaymentMethod(m.id);
      if (!mounted) return;
      _showMessage(ok ? 'Card removed.' : 'Failed to remove card');
      if (ok) await _load();
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: CaddyMoneyTopAppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [
          IconButton(
            tooltip: 'Add card',
            onPressed: _saving ? null : _showAddCardSheet,
            icon: Icon(Icons.add_card, color: cs.primary),
          ),
        ],
      ),
      bottomNavigationBar: context.watch<AuthProvider>().userRole == AppRole.standardUser ? const UserBottomNavBar() : null,
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.center,
                child: Text(
                  'Payment methods',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Your cards', style: tt.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'For now we store only non-sensitive card details (brand, last 4 digits, expiry).',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_loading)
                LinearProgressIndicator(minHeight: 2, color: cs.primary, backgroundColor: cs.surfaceContainerHighest)
              else if (_methods.isEmpty)
                _EmptyCardsState(onAdd: _showAddCardSheet)
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _methods.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => PaymentMethodTile(
                      method: _methods[i],
                      saving: _saving,
                      onSetDefault: () => _setDefault(_methods[i]),
                      onDelete: () => _delete(_methods[i]),
                    ),
                  ),
                ),
              if (!_loading) ...[
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _showAddCardSheet,
                    icon: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                          )
                        : const Icon(Icons.add_card),
                    label: const Text('Add a card'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCardsState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyCardsState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.credit_card, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('No cards yet', style: tt.titleMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Add a card to use it for transfers.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add card'),
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentMethodTile extends StatelessWidget {
  final PaymentMethodModel method;
  final bool saving;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  const PaymentMethodTile({
    super.key,
    required this.method,
    required this.saving,
    required this.onSetDefault,
    required this.onDelete,
  });

  IconData _brandIcon(String brand) {
    switch (brand.toLowerCase()) {
      case 'visa':
        return Icons.credit_card;
      case 'mastercard':
        return Icons.credit_card;
      case 'amex':
        return Icons.credit_card;
      default:
        return Icons.credit_card;
    }
  }

  String _title(PaymentMethodModel m) {
    final nick = (m.nickname ?? '').trim();
    if (nick.isNotEmpty) return nick;
    final brand = m.brand.toUpperCase();
    return '$brand •••• ${m.last4}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
            ),
            child: Icon(_brandIcon(method.brand), color: cs.primary),
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
                        _title(method),
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (method.isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text('Default', style: tt.labelSmall?.copyWith(color: cs.onPrimaryContainer)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Expiry: ${method.expMonth.toString().padLeft(2, '0')}/${method.expYear}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: method.isDefault ? 'Default card' : 'Make default',
            onPressed: saving || method.isDefault ? null : onSetDefault,
            icon: Icon(method.isDefault ? Icons.check_circle : Icons.radio_button_unchecked, color: cs.primary),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: saving ? null : onDelete,
            icon: Icon(Icons.delete_outline, color: cs.error),
          ),
        ],
      ),
    );
  }
}

class _AddCardSheetResult {
  final String cardNumber;
  final int expMonth;
  final int expYear;
  final String? holderName;
  final String? nickname;
  final bool makeDefault;

  const _AddCardSheetResult({
    required this.cardNumber,
    required this.expMonth,
    required this.expYear,
    this.holderName,
    this.nickname,
    required this.makeDefault,
  });
}

class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet();

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  final _cardController = TextEditingController();
  final _holderController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _expMonthController = TextEditingController();
  final _expYearController = TextEditingController();

  bool _makeDefault = true;

  @override
  void dispose() {
    _cardController.dispose();
    _holderController.dispose();
    _nicknameController.dispose();
    _expMonthController.dispose();
    _expYearController.dispose();
    super.dispose();
  }

  void _submit() {
    final month = int.tryParse(_expMonthController.text.trim()) ?? 0;
    final year = int.tryParse(_expYearController.text.trim()) ?? 0;
    context.pop(
      _AddCardSheetResult(
        cardNumber: _cardController.text,
        expMonth: month,
        expYear: year,
        holderName: _holderController.text.trim().isEmpty ? null : _holderController.text.trim(),
        nickname: _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
        makeDefault: _makeDefault,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, bottom: viewInsets.bottom + AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add a card', style: tt.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text('Don’t enter real cards in production. This is a demo storage UI.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _nicknameController,
            decoration: InputDecoration(
              labelText: 'Nickname (optional)',
              prefixIcon: Icon(Icons.label_outline, color: cs.onSurfaceVariant),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _cardController,
            decoration: InputDecoration(
              labelText: 'Card number',
              hintText: '4111 1111 1111 1111',
              prefixIcon: Icon(Icons.credit_card, color: cs.onSurfaceVariant),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _expMonthController,
                  decoration: InputDecoration(
                    labelText: 'Exp. month',
                    hintText: 'MM',
                    prefixIcon: Icon(Icons.calendar_month_outlined, color: cs.onSurfaceVariant),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _expYearController,
                  decoration: InputDecoration(
                    labelText: 'Exp. year',
                    hintText: 'YYYY',
                    prefixIcon: Icon(Icons.calendar_today_outlined, color: cs.onSurfaceVariant),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _holderController,
            decoration: InputDecoration(
              labelText: 'Cardholder name (optional)',
              prefixIcon: Icon(Icons.person_outline, color: cs.onSurfaceVariant),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: AppSpacing.paddingMd,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Expanded(child: Text('Set as default', style: tt.bodyMedium)),
                Switch.adaptive(value: _makeDefault, onChanged: (v) => setState(() => _makeDefault = v)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Save card'),
            ),
          ),
        ],
      ),
    );
  }
}
