import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'package:caddymoney/models/payment_method_model.dart';
import 'package:caddymoney/models/saved_recipient_model.dart';
import 'package:caddymoney/services/recipient_service.dart';
import 'package:caddymoney/services/payment_method_service.dart';
import 'package:caddymoney/services/transaction_service.dart';
import 'package:caddymoney/core/constants/app_constants.dart';
import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/screens/user/widgets/user_bottom_nav_bar.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';

class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  static const double _floatingNavEstimatedHeight = 124;

  final _amountController = TextEditingController();
  final _addRecipientEmailController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedTransferCategory;

  late final VoidCallback _amountListener;

  final RecipientService _recipientService = RecipientService();
  final PaymentMethodService _paymentMethodService = PaymentMethodService();
  final TransactionService _transactionService = TransactionService();

  bool _loadingRecipients = true;
  bool _addingRecipient = false;
  bool _savingRecipient = false;
  List<SavedRecipientModel> _recipients = const [];

  int _step = 0;
  String? _selectedRecipientEmail;
  SavedRecipientModel? _selectedRecipient;

  bool _transferCompleted = false;
  _TransferReceipt? _receipt;

  bool _loadingPaymentMethods = true;
  List<PaymentMethodModel> _paymentMethods = const [];
  String? _selectedPaymentMethodId;

  bool _sending = false;
  @override
  void initState() {
    super.initState();
    _amountListener = () {
      if (!mounted) return;
      // Rebuild so Step 2's CTA enables/disables immediately as the user types.
      if (_step == 1) setState(() {});
    };
    _amountController.addListener(_amountListener);
    _loadRecipients();
    _loadPaymentMethods();
  }

  @override
  void dispose() {
    _amountController.removeListener(_amountListener);
    _amountController.dispose();
    _addRecipientEmailController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipients() async {
    setState(() => _loadingRecipients = true);
    try {
      final list = await _recipientService.listMyRecipients();
      if (!mounted) return;
      setState(() => _recipients = list);
    } catch (e) {
      debugPrint('SendMoneyScreen._loadRecipients failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingRecipients = false);
    }
  }

  Future<void> _loadPaymentMethods() async {
    setState(() => _loadingPaymentMethods = true);
    try {
      final list = await _paymentMethodService.listMyPaymentMethods();
      if (!mounted) return;
      setState(() {
        _paymentMethods = list;
        if (_selectedPaymentMethodId == null && list.isNotEmpty) {
          _selectedPaymentMethodId = list.firstWhere((m) => m.isDefault, orElse: () => list.first).id;
        }
        if (_selectedPaymentMethodId != null && list.indexWhere((m) => m.id == _selectedPaymentMethodId) == -1) {
          _selectedPaymentMethodId = list.isNotEmpty ? list.firstWhere((m) => m.isDefault, orElse: () => list.first).id : null;
        }
      });
    } catch (e) {
      debugPrint('SendMoneyScreen._loadPaymentMethods failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingPaymentMethods = false);
    }
  }
  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _goToStep(int value) {
    if (_transferCompleted) return;
    setState(() => _step = value.clamp(0, 3));
  }

  Future<bool> _showRemoveRecipientSheet(SavedRecipientModel r) async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final res = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remove recipient?', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                r.recipientFullName?.trim().isNotEmpty == true
                    ? 'Do you want to remove ${r.recipientFullName} (${r.recipientEmail}) from your saved recipients?'
                    : 'Do you want to remove ${r.recipientEmail} from your saved recipients?',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.pop(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                      ),
                      child: Text('Cancel', style: TextStyle(color: cs.onSurface)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => context.pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.errorContainer,
                        foregroundColor: cs.onErrorContainer,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                      ),
                      child: const Text('Remove'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    return res ?? false;
  }

  Future<void> _handleRemoveRecipient(SavedRecipientModel r) async {
    final confirmed = await _showRemoveRecipientSheet(r);
    if (!confirmed || !mounted) return;

    try {
      final res = await _recipientService.removeRecipient(recipientUserId: r.recipientUserId);
      if (!mounted) return;
      _showMessage(res.message ?? (res.success ? 'Recipient removed.' : 'Failed to remove recipient'));

      if (res.success) {
        await _loadRecipients();
        if (!mounted) return;
        if ((_selectedRecipient?.recipientUserId ?? '') == r.recipientUserId ||
            (_selectedRecipientEmail ?? '').toLowerCase().trim() == r.recipientEmail.toLowerCase().trim()) {
          setState(() {
            _selectedRecipient = null;
            _selectedRecipientEmail = null;
          });
        }
      }
    } catch (e) {
      debugPrint('SendMoneyScreen._handleRemoveRecipient failed: $e');
      if (!mounted) return;
      _showMessage('Failed to remove recipient');
    }
  }

  bool get _canContinueFromStep1 => (_selectedRecipientEmail ?? '').trim().isNotEmpty;

  bool get _canContinueFromStep2 {
    final amount = _parseAmount(_amountController.text);
    return _canContinueFromStep1 && amount != null && amount > 0 && _selectedTransferCategory != null;
  }

  bool get _canContinueFromStep3 => _canContinueFromStep2 && _selectedPaymentMethodId != null;

  double? _parseAmount(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  Future<void> _handleSend() async {
    if (_sending) return;

    final recipientEmail = (_selectedRecipientEmail ?? '').trim();
    final amount = _parseAmount(_amountController.text);

    if (recipientEmail.isEmpty) {
      _showMessage('Please select a recipient.');
      return;
    }
    if (amount == null || amount <= 0) {
      _showMessage('Please enter a valid amount.');
      return;
    }
    if (_selectedPaymentMethodId == null) {
      _showMessage('Please choose a payment method.');
      return;
    }

    setState(() => _sending = true);
    try {
      final receiverId = await _transactionService.findActiveUserIdByEmail(recipientEmail);
      if (!mounted) return;
      if (receiverId == null) {
        _showMessage('No matching user found for that email.');
        return;
      }

      final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
      final category = _selectedTransferCategory;
      if (category == null || category.trim().isEmpty) {
        _showMessage('Please choose a category.');
        return;
      }

      final res = await _transactionService.transferUserToUser(
        receiverUserId: receiverId,
        amount: amount,
        note: note,
        transferCategory: category,
        paymentMethodId: _selectedPaymentMethodId,
      );

      if (!mounted) return;
      if (!res.success) {
        _showMessage(res.error ?? 'Transfer failed');
        return;
      }

      final pm = _paymentMethods.where((m) => m.id == _selectedPaymentMethodId).cast<PaymentMethodModel?>().firstOrNull;
      setState(() {
        _transferCompleted = true;
        _step = 3;
        _receipt = _TransferReceipt(
          recipientEmail: recipientEmail,
          recipientName: _selectedRecipient?.recipientFullName,
          amount: amount,
          category: category,
          note: note,
          paymentMethodTitle: pm == null ? null : _PaymentMethodSectionSupport.titleFor(pm),
          transactionReference: res.transactionReference,
        );
      });

      _amountController.clear();
      _noteController.clear();
      setState(() => _selectedTransferCategory = null);
    } catch (e) {
      debugPrint('SendMoneyScreen._handleSend failed: $e');
      if (!mounted) return;
      _showMessage('Transfer failed');
    } finally {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }
  Future<void> _handleAddRecipient() async {
    if (_savingRecipient) return;
    setState(() => _savingRecipient = true);
    try {
      final res = await _recipientService.addRecipientByEmail(_addRecipientEmailController.text);
      if (!mounted) return;
      _showMessage(res.message ?? (res.success ? 'Recipient added.' : 'Failed to add recipient'));
      if (res.success) {
        final newlyAddedEmail = _addRecipientEmailController.text.trim();
        _addRecipientEmailController.clear();
        setState(() {
          _addingRecipient = false;
          if (newlyAddedEmail.isNotEmpty) {
            _selectedRecipientEmail = newlyAddedEmail;
          }
        });
        await _loadRecipients();
        if (!mounted) return;
        final matched = _recipients.where((r) => r.recipientEmail.toLowerCase() == newlyAddedEmail.toLowerCase()).cast<SavedRecipientModel?>().firstOrNull;
        if (matched != null) {
          setState(() => _selectedRecipient = matched);
        }
      }
    } finally {
      if (!mounted) return;
      setState(() => _savingRecipient = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final title = _transferCompleted ? 'Transfer complete' : 'Send money';

    final floatingNavConfig = _buildFloatingNavConfig();
    return PopScope(
      canPop: !_transferCompleted,
      onPopInvoked: (didPop) {
        if (_transferCompleted && mounted) context.go(AppRoutes.userHome);
      },
      child: Scaffold(
        appBar: const CaddyMoneyTopAppBar(showLeading: false),
        bottomNavigationBar: const UserBottomNavBar(),
        body: SafeArea(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: AppSpacing.paddingLg.copyWith(bottom: AppSpacing.lg + (_transferCompleted ? 0 : _floatingNavEstimatedHeight)),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Text(
                            title,
                            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        StepHeader(step: _step, locked: _transferCompleted, onTapStep: _goToStep),
                        const SizedBox(height: AppSpacing.lg),
                        if (_transferCompleted) ...[
                          TransferSuccessPanel(receipt: _receipt),
                        ] else ...[
                          if (_step == 0)
                            Step1Recipient(
                              titleStyle: tt.titleLarge,
                              loadingRecipients: _loadingRecipients,
                              recipients: _recipients,
                              addingRecipient: _addingRecipient,
                              savingRecipient: _savingRecipient,
                              addEmailController: _addRecipientEmailController,
                              selectedRecipientEmail: _selectedRecipientEmail,
                              onTapRecipient: (r) {
                                setState(() {
                                  _selectedRecipientEmail = r.recipientEmail;
                                  _selectedRecipient = r;
                                });
                              },
                              onLongPressRecipient: _handleRemoveRecipient,
                              onToggleAdd: () => setState(() => _addingRecipient = !_addingRecipient),
                              onCancelAdd: () {
                                _addRecipientEmailController.clear();
                                setState(() => _addingRecipient = false);
                              },
                              onAdd: _handleAddRecipient,
                            ),
                          if (_step == 1)
                            Step2Details(
                              recipient: _selectedRecipient,
                              recipientEmail: _selectedRecipientEmail,
                              amountController: _amountController,
                              selectedCategory: _selectedTransferCategory,
                              onChangedCategory: (v) => setState(() => _selectedTransferCategory = v),
                              noteController: _noteController,
                            ),
                          if (_step == 2)
                            Step3Payment(
                              loadingPaymentMethods: _loadingPaymentMethods,
                              paymentMethods: _paymentMethods,
                              selectedPaymentMethodId: _selectedPaymentMethodId,
                              onSelectPaymentMethod: (id) => setState(() => _selectedPaymentMethodId = id),
                              onManage: () async {
                                await context.push(AppRoutes.paymentMethods);
                                if (!mounted) return;
                                await _loadPaymentMethods();
                              },
                              onRefresh: _loadPaymentMethods,
                            ),
                          if (_step == 3)
                            Step4Review(
                              recipient: _selectedRecipient,
                              recipientEmail: _selectedRecipientEmail,
                              amount: _parseAmount(_amountController.text),
                              category: _selectedTransferCategory,
                              note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
                              paymentMethod: _paymentMethods.where((m) => m.id == _selectedPaymentMethodId).cast<PaymentMethodModel?>().firstOrNull,
                              sending: _sending,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (!_transferCompleted)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                    child: SendMoneyFloatingNav(
                      backLabel: floatingNavConfig.backLabel,
                      forwardLabel: floatingNavConfig.forwardLabel,
                      showBack: floatingNavConfig.showBack,
                      backEnabled: floatingNavConfig.backEnabled,
                      forwardEnabled: floatingNavConfig.forwardEnabled,
                      forwardIcon: floatingNavConfig.forwardIcon,
                      forwardLoading: floatingNavConfig.forwardLoading,
                      onBack: floatingNavConfig.onBack,
                      onForward: floatingNavConfig.onForward,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  _FloatingNavConfig _buildFloatingNavConfig() {
    final isFirst = _step == 0;
    final isLast = _step == 3;

    VoidCallback? onBack;
    if (_sending) {
      onBack = null;
    } else if (isFirst) {
      onBack = () => context.go(AppRoutes.userHome);
    } else {
      onBack = () => _goToStep(_step - 1);
    }

    final bool forwardEnabled;
    VoidCallback? onForward;
    if (_sending) {
      onForward = null;
      forwardEnabled = false;
    } else if (isLast) {
      onForward = _handleSend;
      forwardEnabled = true;
    } else if (_step == 0) {
      forwardEnabled = _canContinueFromStep1;
      onForward = forwardEnabled ? () => _goToStep(1) : null;
    } else if (_step == 1) {
      forwardEnabled = _canContinueFromStep2;
      onForward = forwardEnabled ? () => _goToStep(2) : null;
    } else {
      forwardEnabled = _canContinueFromStep3;
      onForward = forwardEnabled ? () => _goToStep(3) : null;
    }

    return _FloatingNavConfig(
      backLabel: 'Back',
      forwardLabel: isLast ? 'Send' : 'Continue',
      showBack: !isFirst,
      backEnabled: !_sending,
      forwardEnabled: forwardEnabled,
      forwardIcon: isLast ? Icons.send_rounded : Icons.arrow_forward_rounded,
      forwardLoading: isLast && _sending,
      onBack: onBack,
      onForward: onForward,
    );
  }
}

class _FloatingNavConfig {
  final String backLabel;
  final String forwardLabel;
  final bool showBack;
  final bool backEnabled;
  final bool forwardEnabled;
  final IconData forwardIcon;
  final bool forwardLoading;
  final VoidCallback? onBack;
  final VoidCallback? onForward;

  const _FloatingNavConfig({
    required this.backLabel,
    required this.forwardLabel,
    required this.showBack,
    required this.backEnabled,
    required this.forwardEnabled,
    required this.forwardIcon,
    required this.forwardLoading,
    required this.onBack,
    required this.onForward,
  });
}

class _TransferReceipt {
  final String recipientEmail;
  final String? recipientName;
  final double amount;
  final String? category;
  final String? note;
  final String? paymentMethodTitle;
  final String? transactionReference;

  const _TransferReceipt({
    required this.recipientEmail,
    required this.recipientName,
    required this.amount,
    required this.category,
    required this.note,
    required this.paymentMethodTitle,
    required this.transactionReference,
  });
}

class StepHeader extends StatefulWidget {
  final int step;
  final bool locked;
  final ValueChanged<int> onTapStep;

  const StepHeader({super.key, required this.step, required this.locked, required this.onTapStep});

  @override
  State<StepHeader> createState() => _StepHeaderState();
}

class _StepHeaderState extends State<StepHeader> {
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _stepKeys = List.generate(4, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureActiveStepVisible(animated: false));
  }

  @override
  void didUpdateWidget(covariant StepHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) {
      // Important UX detail:
      // - When progressing forward, auto-scroll to keep the active step fully visible.
      // - When going backward, generally do NOT auto-scroll (prevents a jarring reset/jump),
      //   except when returning to the first step where we must reveal the start of the list.
      final movedForward = widget.step > oldWidget.step;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.step == 0) {
          // Ensure the first step is never hidden after the user navigates back.
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
            );
          }
          return;
        }
        if (movedForward) _ensureActiveStepVisible(animated: true);
      });
    }
  }

  double _alignmentForStep(int step) {
    // Keep the last pill slightly left of center so it's comfortably readable
    // (and avoids feeling “stuck” to the right edge).
    if (step >= _stepKeys.length - 1) return 0.42;
    return 0.5;
  }

  void _ensureActiveStepVisible({required bool animated}) {
    if (!mounted) return;
    final idx = widget.step.clamp(0, _stepKeys.length - 1);
    final ctx = _stepKeys[idx].currentContext;
    if (ctx == null) return;

    // Centers the active step (or at least makes it fully visible) with a smooth, natural animation.
    Scrollable.ensureVisible(
      ctx,
      alignment: _alignmentForStep(idx),
      duration: animated ? const Duration(milliseconds: 260) : Duration.zero,
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Padding(
        // Trailing padding ensures the final step (“Review”) never appears clipped
        // against the right edge, especially on smaller widths.
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: Row(
          children: [
            KeyedSubtree(
              key: _stepKeys[0],
              child: _StepPill(
                index: 0,
                current: widget.step,
                locked: widget.locked,
                title: 'Recipient',
                onTap: () => widget.onTapStep(0),
              ),
            ),
            const _StepDivider(),
            KeyedSubtree(
              key: _stepKeys[1],
              child: _StepPill(
                index: 1,
                current: widget.step,
                locked: widget.locked,
                title: 'Details',
                onTap: () => widget.onTapStep(1),
              ),
            ),
            const _StepDivider(),
            KeyedSubtree(
              key: _stepKeys[2],
              child: _StepPill(
                index: 2,
                current: widget.step,
                locked: widget.locked,
                title: 'Payment',
                onTap: () => widget.onTapStep(2),
              ),
            ),
            const _StepDivider(),
            KeyedSubtree(
              key: _stepKeys[3],
              child: _StepPill(
                index: 3,
                current: widget.step,
                locked: widget.locked,
                title: 'Review',
                onTap: () => widget.onTapStep(3),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (widget.locked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Locked', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onPrimaryContainer)),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepDivider extends StatelessWidget {
  const _StepDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      color: cs.outlineVariant.withValues(alpha: 0.35),
    );
  }
}

class _StepPill extends StatelessWidget {
  final int index;
  final int current;
  final bool locked;
  final String title;
  final VoidCallback onTap;

  const _StepPill({required this.index, required this.current, required this.locked, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = index == current;
    return InkWell(
      onTap: locked ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? cs.onPrimaryContainer : cs.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class Step1Recipient extends StatelessWidget {
  final TextStyle? titleStyle;
  final bool loadingRecipients;
  final List<SavedRecipientModel> recipients;
  final bool addingRecipient;
  final bool savingRecipient;
  final TextEditingController addEmailController;
  final String? selectedRecipientEmail;
  final ValueChanged<SavedRecipientModel> onTapRecipient;
  final ValueChanged<SavedRecipientModel> onLongPressRecipient;
  final VoidCallback onToggleAdd;
  final VoidCallback onCancelAdd;
  final VoidCallback onAdd;

  const Step1Recipient({
    super.key,
    required this.titleStyle,
    required this.loadingRecipients,
    required this.recipients,
    required this.addingRecipient,
    required this.savingRecipient,
    required this.addEmailController,
    required this.selectedRecipientEmail,
    required this.onTapRecipient,
    required this.onLongPressRecipient,
    required this.onToggleAdd,
    required this.onCancelAdd,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Transfer to:', style: titleStyle)),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onToggleAdd,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                side: BorderSide(color: cs.primary.withValues(alpha: 0.7)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                foregroundColor: cs.primary,
              ),
              icon: Icon(addingRecipient ? Icons.close : Icons.person_add_alt_1, color: cs.primary, size: 18),
              label: Text(addingRecipient ? 'Close' : 'Add recipient', style: tt.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SavedRecipientsSection(
          loading: loadingRecipients,
          recipients: recipients,
          adding: addingRecipient,
          saving: savingRecipient,
          addEmailController: addEmailController,
          selectedEmail: selectedRecipientEmail,
          onTapRecipient: onTapRecipient,
          onLongPressRecipient: onLongPressRecipient,
          onCancelAdd: onCancelAdd,
          onAdd: onAdd,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class Step2Details extends StatelessWidget {
  final SavedRecipientModel? recipient;
  final String? recipientEmail;
  final TextEditingController amountController;
  final String? selectedCategory;
  final ValueChanged<String?> onChangedCategory;
  final TextEditingController noteController;

  const Step2Details({
    super.key,
    required this.recipient,
    required this.recipientEmail,
    required this.amountController,
    required this.selectedCategory,
    required this.onChangedCategory,
    required this.noteController,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final email = (recipientEmail ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
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
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.person, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipient?.recipientFullName?.trim().isNotEmpty == true ? recipient!.recipientFullName!.trim() : 'Recipient', style: tt.titleMedium),
                    const SizedBox(height: 2),
                    Text(email, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _AmountQuickPickRow(amountController: amountController),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          value: selectedCategory,
          decoration: InputDecoration(
            labelText: 'Category',
            prefixIcon: Icon(Icons.category_outlined, color: cs.onSurfaceVariant),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          items: AppConstants.businessCategories
              .map((c) => DropdownMenuItem<String>(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
              .toList(growable: false),
          onChanged: onChangedCategory,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: noteController,
          decoration: InputDecoration(
            labelText: 'Note (optional)',
            prefixIcon: Icon(Icons.chat_bubble_outline, color: cs.onSurfaceVariant),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          maxLines: 2,
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }
}

class _AmountQuickPickRow extends StatelessWidget {
  final TextEditingController amountController;
  const _AmountQuickPickRow({required this.amountController});

  double? _parseAmount(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  void _setAmount(BuildContext context, double value) {
    final text = value % 1 == 0 ? value.toStringAsFixed(0) : value.toString();
    amountController.value = amountController.value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: amountController,
      builder: (context, value, _) {
        final currentAmount = _parseAmount(value.text);
        final options = const [10.0, 20.0, 50.0];

        return LayoutBuilder(
          builder: (context, constraints) {
            final stackInOneRow = constraints.maxWidth >= 360;
            final quickPicks = Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final v in options)
                  _QuickAmountPill(
                    amount: v,
                    selected: currentAmount != null && (currentAmount - v).abs() < 0.001,
                    onTap: () => _setAmount(context, v),
                  ),
              ],
            );

            final field = TextField(
              controller: amountController,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixIcon: Icon(Icons.euro, color: cs.onSurfaceVariant),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            );

            if (!stackInOneRow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  quickPicks,
                  const SizedBox(height: AppSpacing.sm),
                  field,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: quickPicks),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(width: 170, child: field),
              ],
            );
          },
        );
      },
    );
  }
}

class _QuickAmountPill extends StatelessWidget {
  final double amount;
  final bool selected;
  final VoidCallback onTap;

  const _QuickAmountPill({required this.amount, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final amountLabel = amount % 1 == 0 ? amount.toStringAsFixed(0) : amount.toString();

    final bg = selected ? cs.primaryContainer : cs.surfaceContainerHighest.withValues(alpha: 0.55);
    final border = selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5);
    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border, width: selected ? 1.2 : 1),
          ),
          child: Text(
            '€$amountLabel',
            style: tt.labelLarge?.copyWith(color: fg, fontWeight: selected ? FontWeight.w800 : FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class Step3Payment extends StatelessWidget {
  final bool loadingPaymentMethods;
  final List<PaymentMethodModel> paymentMethods;
  final String? selectedPaymentMethodId;
  final ValueChanged<String> onSelectPaymentMethod;
  final VoidCallback onManage;
  final VoidCallback onRefresh;

  const Step3Payment({
    super.key,
    required this.loadingPaymentMethods,
    required this.paymentMethods,
    required this.selectedPaymentMethodId,
    required this.onSelectPaymentMethod,
    required this.onManage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaymentMethodSection(
          loading: loadingPaymentMethods,
          methods: paymentMethods,
          selectedId: selectedPaymentMethodId,
          onSelect: onSelectPaymentMethod,
          onManage: onManage,
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}

class Step4Review extends StatelessWidget {
  final SavedRecipientModel? recipient;
  final String? recipientEmail;
  final double? amount;
  final String? category;
  final String? note;
  final PaymentMethodModel? paymentMethod;
  final bool sending;

  const Step4Review({
    super.key,
    required this.recipient,
    required this.recipientEmail,
    required this.amount,
    required this.category,
    required this.note,
    required this.paymentMethod,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final email = (recipientEmail ?? '').trim();
    final displayName = recipient?.recipientFullName?.trim().isNotEmpty == true ? recipient!.recipientFullName!.trim() : null;
    final pmTitle = paymentMethod == null ? null : _PaymentMethodSectionSupport.titleFor(paymentMethod!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Review transfer', style: tt.titleMedium),
              const SizedBox(height: AppSpacing.md),
              _ReviewRow(label: 'Recipient', value: displayName == null ? email : '$displayName ($email)'),
              const SizedBox(height: AppSpacing.sm),
              _ReviewRow(label: 'Amount', value: amount == null ? '—' : '€ ${amount!.toStringAsFixed(2)}'),
              const SizedBox(height: AppSpacing.sm),
              _ReviewRow(label: 'Category', value: (category ?? '').trim().isEmpty ? '—' : category!.trim()),
              const SizedBox(height: AppSpacing.sm),
              _ReviewRow(label: 'Payment method', value: pmTitle ?? '—'),
              if (note?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppSpacing.sm),
                _ReviewRow(label: 'Note', value: note!.trim()),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SendMoneyFloatingNav extends StatelessWidget {
  final String backLabel;
  final String forwardLabel;
  final bool showBack;
  final bool backEnabled;
  final bool forwardEnabled;
  final IconData forwardIcon;
  final bool forwardLoading;
  final VoidCallback? onBack;
  final VoidCallback? onForward;

  const SendMoneyFloatingNav({
    super.key,
    required this.backLabel,
    required this.forwardLabel,
    required this.showBack,
    required this.backEnabled,
    required this.forwardEnabled,
    required this.forwardIcon,
    required this.forwardLoading,
    required this.onBack,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const gap = 36.0;
    const buttonSize = 64.0;

    // On the first step we intentionally hide the back button.
    // In that case, keep the forward button perfectly centered (no placeholder).
    if (!showBack) {
      return Center(
        child: _CircularNavButton(
          label: forwardLabel,
          enabled: forwardEnabled,
          style: _CircularNavStyle.filled,
          icon: forwardIcon,
          loading: forwardLoading,
          onTap: onForward,
          labelStyle: tt.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircularNavButton(
          label: backLabel,
          enabled: backEnabled,
          style: _CircularNavStyle.outlined,
          icon: Icons.arrow_back_rounded,
          onTap: onBack,
          labelStyle: tt.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: gap),
        _CircularNavButton(
          label: forwardLabel,
          enabled: forwardEnabled,
          style: _CircularNavStyle.filled,
          icon: forwardIcon,
          loading: forwardLoading,
          onTap: onForward,
          labelStyle: tt.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

enum _CircularNavStyle { outlined, filled }

class _CircularNavButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final _CircularNavStyle style;
  final IconData icon;
  final bool loading;
  final VoidCallback? onTap;
  final TextStyle? labelStyle;

  const _CircularNavButton({
    required this.label,
    required this.enabled,
    required this.style,
    required this.icon,
    required this.onTap,
    required this.labelStyle,
    this.loading = false,
  });

  static const double _size = 64;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final iconColor = style == _CircularNavStyle.filled ? cs.onPrimary : cs.primary;
    final borderColor = cs.primary.withValues(alpha: 0.65);
    final bgColor = style == _CircularNavStyle.filled ? cs.primary : Colors.transparent;

    final gradient = style == _CircularNavStyle.filled
        ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.transactionFilterSelectedGradient)
        : null;

    final content = SizedBox(
      width: _size,
      height: _size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: gradient == null ? bgColor : null,
          gradient: gradient,
          shape: BoxShape.circle,
          border: style == _CircularNavStyle.outlined ? Border.all(color: borderColor, width: 1.5) : null,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: loading
                ? SizedBox(
                    key: const ValueKey('loading'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
                  )
                : Icon(icon, key: ValueKey(icon), color: iconColor, size: 30),
          ),
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              onTap: enabled ? onTap : null,
              customBorder: const CircleBorder(),
              child: content,
            ),
          ),
          const SizedBox(height: 10),
          Text(label.toLowerCase(), style: labelStyle),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(value, style: tt.bodyMedium, softWrap: true)),
      ],
    );
  }
}

class TransferSuccessPanel extends StatelessWidget {
  final _TransferReceipt? receipt;
  const TransferSuccessPanel({super.key, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final r = receipt;
    final recipientLabel = (r?.recipientName?.trim().isNotEmpty == true)
        ? r!.recipientName!.trim()
        : (r?.recipientEmail ?? '').trim();
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.check_circle, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Success', style: tt.titleLarge),
                    const SizedBox(height: 2),
                    Text('The money has been sent to $recipientLabel', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _ReviewRow(label: 'Recipient', value: recipientLabel),
          const SizedBox(height: AppSpacing.sm),
          _ReviewRow(label: 'Amount', value: r == null ? '—' : '€ ${r.amount.toStringAsFixed(2)}'),
          const SizedBox(height: AppSpacing.sm),
          if (r?.category?.trim().isNotEmpty == true) _ReviewRow(label: 'Category', value: r!.category!.trim()),
          if (r?.category?.trim().isNotEmpty == true) const SizedBox(height: AppSpacing.sm),
          _ReviewRow(label: 'Payment method', value: r?.paymentMethodTitle ?? '—'),
          if (r?.note?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            _ReviewRow(label: 'Note', value: r!.note!.trim()),
          ],
          if (r?.transactionReference?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            _ReviewRow(label: 'Reference', value: r!.transactionReference!.trim()),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            'For security, you cannot return to the send flow once a transfer is completed.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class SavedRecipientsSection extends StatelessWidget {
  final bool loading;
  final List<SavedRecipientModel> recipients;
  final bool adding;
  final bool saving;
  final TextEditingController addEmailController;
  final VoidCallback onCancelAdd;
  final VoidCallback onAdd;
  final String? selectedEmail;
  final ValueChanged<SavedRecipientModel> onTapRecipient;
  final ValueChanged<SavedRecipientModel> onLongPressRecipient;

  const SavedRecipientsSection({
    super.key,
    required this.loading,
    required this.recipients,
    required this.adding,
    required this.saving,
    required this.addEmailController,
    required this.onCancelAdd,
    required this.onAdd,
    required this.selectedEmail,
    required this.onTapRecipient,
    required this.onLongPressRecipient,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Saved recipients', style: tt.titleMedium)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (loading) ...[
            LinearProgressIndicator(minHeight: 2, color: cs.primary, backgroundColor: cs.surfaceContainerHighest),
            const SizedBox(height: AppSpacing.md),
          ] else if (recipients.isEmpty) ...[
            Text('No saved recipients yet.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
          ] else ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: recipients
                  .map(
                    (r) {
                      final isSelected = (selectedEmail ?? '').trim().isNotEmpty && r.recipientEmail.toLowerCase() == selectedEmail!.trim().toLowerCase();
                      return GestureDetector(
                        onLongPress: () => onLongPressRecipient(r),
                        child: InputChip(
                          label: Text(
                            r.recipientFullName?.isNotEmpty == true
                                ? '${r.recipientFullName} • ${r.recipientEmail}'
                                : r.recipientEmail,
                            overflow: TextOverflow.ellipsis,
                          ),
                          avatar: Icon(
                            isSelected ? Icons.person : Icons.person_outline,
                            color: isSelected ? cs.primary : cs.onSurfaceVariant,
                            size: 18,
                          ),
                          onPressed: () => onTapRecipient(r),
                          labelStyle: TextStyle(
                            color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          ),
                          backgroundColor: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.45),
                              width: isSelected ? 1.2 : 1,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: adding
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: addEmailController,
                        decoration: InputDecoration(
                          labelText: 'Recipient email',
                          prefixIcon: Icon(Icons.alternate_email, color: cs.onSurfaceVariant),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => onAdd(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: saving ? null : onAdd,
                              icon: saving
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                                    )
                                  : const Icon(Icons.add),
                              label: const Text('Add'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          OutlinedButton(
                            onPressed: saving ? null : onCancelAdd,
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class PaymentMethodSection extends StatelessWidget {
  final bool loading;
  final List<PaymentMethodModel> methods;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onManage;
  final VoidCallback onRefresh;

  const PaymentMethodSection({
    super.key,
    required this.loading,
    required this.methods,
    required this.selectedId,
    required this.onSelect,
    required this.onManage,
    required this.onRefresh,
  });

  IconData _brandIcon(String brand) {
    switch (brand.toLowerCase()) {
      case 'mastercard':
        return Icons.credit_card;
      case 'amex':
      case 'american express':
        return Icons.credit_card;
      case 'visa':
      default:
        return Icons.credit_card;
    }
  }

  String _titleFor(PaymentMethodModel m) => _PaymentMethodSectionSupport.titleFor(m);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final visible = methods.take(3).toList();
    final hasMore = methods.length > visible.length;

    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingMd,
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
              Expanded(child: Text('Payment method', style: tt.titleMedium)),
              IconButton(
                tooltip: 'Refresh',
                onPressed: loading ? null : onRefresh,
                icon: Icon(Icons.refresh, color: cs.primary),
              ),
              TextButton.icon(
                onPressed: onManage,
                icon: Icon(Icons.settings_outlined, color: cs.primary),
                label: Text('Manage', style: TextStyle(color: cs.primary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (loading)
            LinearProgressIndicator(minHeight: 2, color: cs.primary, backgroundColor: cs.surfaceContainerHighest)
          else if (methods.isEmpty)
            Text('No cards saved yet. Tap “Manage” to add one.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))
          else
            ...[
              for (final m in visible)
                RadioListTile<String>(
                  value: m.id,
                  groupValue: selectedId,
                  onChanged: (v) {
                    if (v == null) return;
                    onSelect(v);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(_brandIcon(m.brand), color: cs.onSurfaceVariant),
                  title: Text(_titleFor(m), style: tt.bodyMedium),
                  subtitle: Text(
                    'Exp ${m.expMonth.toString().padLeft(2, '0')}/${m.expYear.toString().padLeft(2, '0')}${m.isDefault ? ' • Default' : ''}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              if (hasMore)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onManage,
                    child: Text('Show all (${methods.length})', style: TextStyle(color: cs.primary)),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

class _PaymentMethodSectionSupport {
  static String titleFor(PaymentMethodModel m) {
    final nick = (m.nickname ?? '').trim();
    if (nick.isNotEmpty) return nick;
    return '${m.brand.toUpperCase()} •••• ${m.last4}';
  }
}

extension _FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
