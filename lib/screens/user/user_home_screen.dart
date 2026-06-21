import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:caddymoney/widgets/ring_flash_orbit.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/core/enums/transaction_type.dart';
import 'package:caddymoney/models/transaction_model.dart';
import 'package:caddymoney/services/transaction_service.dart';
import 'package:caddymoney/services/wallet_service.dart';
import 'package:caddymoney/screens/user/widgets/user_bottom_nav_bar.dart';
import 'package:caddymoney/widgets/support_notifications_app_bar.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';
import 'package:caddymoney/widgets/caddy_money_wordmark.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  final TransactionService _transactionService = TransactionService();
  final WalletService _walletService = WalletService();

  static const double _headerCollapseRange = 220;
  late final ScrollController _scrollController;

  bool _loadingServiceBalances = true;
  List<CategoryBalance> _serviceBalances = const [];

  bool _loadingBalance = true;
  double? _balance;
  String? _currencyCode;

  bool _loadingTotals = true;
  double? _totalReceived;
  double? _totalSpent;

  double get _availableAmount {
    final received = _totalReceived ?? 0;
    final spent = _totalSpent ?? 0;
    return received - spent;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadBalance();
    _loadTotals();
    _loadServiceBalances();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _collapseT() {
    if (!_scrollController.hasClients) return 0;
    final offset = _scrollController.offset;
    if (offset <= 0) return 0;
    return (offset / _headerCollapseRange).clamp(0.0, 1.0);
  }

  Future<void> _loadBalance() async {
    setState(() => _loadingBalance = true);
    try {
      final wallet = await _walletService.getMyUserWallet();
      if (!mounted) return;
      setState(() {
        // We display the available amount as: total received - total spent.
        // Keep the wallet query only to obtain a reliable currency code.
        _balance = wallet?.balance;
        _currencyCode = wallet?.currencyCode;
      });
    } catch (e) {
      debugPrint('UserHomeScreen._loadBalance failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingBalance = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadBalance(),
      _loadTotals(),
      _loadServiceBalances(),
    ]);
  }

  Future<void> _loadTotals() async {
    setState(() => _loadingTotals = true);
    try {
      final totals = await _transactionService.getMyReceivedAndMerchantSpendTotals();
      if (!mounted) return;
      setState(() {
        _totalReceived = totals.totalReceived;
        _totalSpent = totals.totalSpentAtMerchants;
        // Prefer wallet currency (source of truth), but fall back to totals.
        _currencyCode ??= totals.currencyCode;
      });
    } catch (e) {
      debugPrint('UserHomeScreen._loadTotals failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingTotals = false);
    }
  }

  Future<void> _loadServiceBalances() async {
    setState(() => _loadingServiceBalances = true);
    try {
      // Home should reflect Transactions → Coupon (received coupons), but show
      // the remaining amount after subtracting what has already been spent at
      // merchants (Paid) for the same category.
      final list = await _transactionService.getMyRemainingCouponCategoryBalances();
      if (!mounted) return;
      setState(() => _serviceBalances = list);
    } catch (e) {
      // Keep UI resilient; home screen should not crash.
      debugPrint('UserHomeScreen._loadServiceBalances failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loadingServiceBalances = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final cs = Theme.of(context).colorScheme;

    // Only show *available* coupon amounts (what the user has received and can still spend).
    final availableServiceBalances = _serviceBalances.where((b) => b.balance > 0).toList(growable: false);

    return Scaffold(
      appBar: const SupportNotificationsAppBar(showLeading: false, requesterType: SupportRequesterType.user),
      bottomNavigationBar: const UserBottomNavBar(),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _scrollController,
              builder: (context, _) {
                final t = _collapseT();
                return _UserHomeBackground(collapseT: t);
              },
            ),
          ),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.paddingLg.left,
                        AppSpacing.paddingLg.top,
                        AppSpacing.paddingLg.right,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: AnimatedBuilder(
                          animation: _scrollController,
                          builder: (context, _) {
                            final curvedT = Curves.easeOutCubic.transform(_collapseT());
                            final opacity = (1 - curvedT).clamp(0.0, 1.0);
                            final dy = -22 * curvedT;

                            return RepaintBoundary(
                              child: Transform.translate(
                                offset: Offset(0, dy),
                                child: Opacity(
                                  opacity: opacity,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${l10n.welcomeBack},',
                                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                              color: Colors.white.withValues(alpha: 0.92),
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.15,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        user?.fullName ?? 'User',
                                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              height: 1.05,
                                              letterSpacing: -0.3,
                                              color: Colors.white,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xl),
                                      BalanceWithQrButton(
                                        balance: _availableAmount,
                                        currencyCode: _currencyCode,
                                        isLoading: _loadingTotals,
                                        onTapQr: () async {
                                          // The QR flow (scan → confirm → pay) happens on a separate route.
                                          // When the user returns to Home, refresh totals so the new payment
                                          // is immediately reflected.
                                          await context.push(AppRoutes.qrScan);
                                          if (!mounted) return;
                                          await _refresh();
                                        },
                                      ),
                                      const SizedBox(height: AppSpacing.lg),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          availableServiceBalances.length > 1 ? 'Coupons disponibles' : 'Coupon disponible',
                                          textAlign: TextAlign.left,
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.2,
                                                color: Colors.white,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.xs,
                        AppSpacing.md,
                        AppSpacing.lg,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(
                          [
                            if (_loadingServiceBalances)
                              Container(
                                padding: AppSpacing.paddingMd,
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withValues(alpha: 0.20),
                                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                                  borderRadius: BorderRadius.circular(AppRadius.lg),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 42, height: 42, child: CircularProgressIndicator(strokeWidth: 2)),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Text(
                                        'Loading recent transactions…',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (availableServiceBalances.isEmpty)
                              Container(
                                padding: AppSpacing.paddingMd,
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withValues(alpha: 0.20),
                                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                                  borderRadius: BorderRadius.circular(AppRadius.lg),
                                ),
                                child: Text(
                                  'No available coupons yet.',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              )
                            else
                              ...availableServiceBalances.map((g) => HomeServiceBalanceTile(balance: g)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserHomeBackground extends StatelessWidget {
  final double collapseT;

  const _UserHomeBackground({this.collapseT = 0});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    // Per latest direction: dark mode background should be a solid color (no gradients).
    // Keep light mode with the existing soft gradient treatment.
    if (isDark) {
      return const DecoratedBox(decoration: BoxDecoration(color: AppColors.darkBackground));
    }

    final colors = AppColors.homeBackgroundGradientLight;
    const blobOpacity = 0.14;

    final curvedT = Curves.easeOutCubic.transform(collapseT.clamp(0.0, 1.0));
    final blobsOpacity = (1 - (curvedT * 0.92)).clamp(0.0, 1.0);
    final dy = -28 * curvedT;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
      ),
      child: Stack(
        children: [
          IgnorePointer(
            child: Opacity(
              opacity: blobsOpacity,
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Stack(
                  children: [
                    Positioned(
                      right: -120,
                      top: -140,
                      child: _SoftBlob(
                        diameter: 320,
                        color: AppColors.homeBlobTeal.withValues(alpha: blobOpacity),
                        blurSigma: 26,
                      ),
                    ),
                    Positioned(
                      left: -140,
                      top: 180,
                      child: _SoftBlob(
                        diameter: 360,
                        color: AppColors.homeBlobMint.withValues(alpha: blobOpacity * 0.90),
                        blurSigma: 28,
                      ),
                    ),
                    Positioned(
                      right: -180,
                      bottom: -220,
                      child: _SoftBlob(
                        diameter: 460,
                        color: AppColors.homeBlobCoral.withValues(alpha: blobOpacity * 0.55),
                        blurSigma: 30,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.surface.withValues(alpha: 0.00),
                      cs.surface.withValues(alpha: 0.02),
                      cs.surface.withValues(alpha: 0.05),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftBlob extends StatelessWidget {
  final double diameter;
  final Color color;
  final double blurSigma;

  const _SoftBlob({required this.diameter, required this.color, required this.blurSigma});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: Container(width: diameter, height: diameter, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

class HomeServiceBalanceTile extends StatelessWidget {
  final CategoryBalance balance;

  const HomeServiceBalanceTile({super.key, required this.balance});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Ticket-style coupon card (requested UI). We keep colors theme-consistent.
    final stripColor = AppColors.couponColorForCategory(balance.category);
    final borderColor = cs.outlineVariant.withValues(alpha: 0.35);
    final surfaceColor = cs.surface;
    final categoryTextColor = cs.onSurfaceVariant.withValues(alpha: isDark ? 0.74 : 0.58);
    final categoryUnderlineColor = cs.onSurfaceVariant.withValues(alpha: isDark ? 0.34 : 0.28);
    // Ticket “holes” color (requested).
    // Light: lavender (matches your reference). Dark: keep the previous “cut-out” look.
    final holeColor = isDark ? Theme.of(context).scaffoldBackgroundColor : AppColors.couponTicketHole;

    final amountText = balance.balance.toStringAsFixed(2).replaceAll('.', ',');
    final title = balance.category.toUpperCase();

    final amountStyle = (Theme.of(context).textTheme.displaySmall ?? Theme.of(context).textTheme.headlineLarge)?.copyWith(
          fontWeight: FontWeight.w900,
          // Slightly tighter line-height to avoid rare bottom overflows on small devices.
          height: 0.95,
        );

    final baseAmountFontSize = amountStyle?.fontSize ?? 36;
    final euroStyle = amountStyle?.copyWith(
      fontSize: baseAmountFontSize * 0.5,
      fontWeight: FontWeight.w800,
      height: 1.0,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        onTap: null,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          height: 116,
          // Important: do NOT clip this container; otherwise the shadow gets clipped into
          // a straight edge on the right side. We clip only the inner content.
          decoration: BoxDecoration(
            color: surfaceColor,
            boxShadow: [
              BoxShadow(
                // Softer, more premium shadow (keep depth, reduce harshness).
                color: cs.shadow.withValues(alpha: isDark ? 0.24 : 0.13),
                blurRadius: 34,
                spreadRadius: -14,
                offset: const Offset(12, 16),
              ),
              BoxShadow(
                color: cs.shadow.withValues(alpha: isDark ? 0.14 : 0.08),
                blurRadius: 14,
                spreadRadius: -8,
                offset: const Offset(4, 7),
              ),
            ],
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 92,
                      height: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(stripColor, Colors.white, isDark ? 0.06 : 0.16) ?? stripColor,
                              Color.lerp(stripColor, Colors.black, isDark ? 0.10 : 0.06) ?? stripColor,
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(AppRadius.xl),
                            bottomLeft: Radius.circular(AppRadius.xl),
                          ),
                        ),
                        child: Center(
                          child: Icon(AppColors.couponIconForCategory(balance.category), color: Colors.white.withValues(alpha: 0.96), size: 34),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        // Use a bit less vertical padding so the large amount text never overflows.
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: categoryTextColor,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: 2,
                              width: 140,
                              decoration: BoxDecoration(
                                color: categoryUnderlineColor,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(text: amountText, style: amountStyle),
                                          TextSpan(text: '€', style: euroStyle),
                                        ],
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Right-side stamp area (QR icon + wordmark).
                    _CouponStamp(stripColor: stripColor),
                  ],
                ),

                // Perforation effect between the strip and the body.
                Positioned(
                  left: 92 - 10,
                  top: 14,
                  child: _TicketHole(color: holeColor, isOutlined: !isDark),
                ),
                Positioned(
                  left: 92 - 10,
                  top: (116 / 2) - 10,
                  child: _TicketHole(color: holeColor, isOutlined: !isDark),
                ),
                Positioned(
                  left: 92 - 10,
                  bottom: 14,
                  child: _TicketHole(color: holeColor, isOutlined: !isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CouponStamp extends StatelessWidget {
  final Color stripColor;

  const _CouponStamp({required this.stripColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stampBg = (isDark ? cs.surfaceContainerHighest : cs.surfaceContainerHigh).withValues(alpha: isDark ? 0.50 : 0.70);
    final dividerColor = cs.outlineVariant.withValues(alpha: 0.35);
    final qrColor = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.92);

    return SizedBox(
      width: 96,
      height: double.infinity,
      child: Row(
        children: [
          // Perforated vertical divider.
          SizedBox(
            width: 12,
            height: double.infinity,
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) => CustomPaint(
                  size: Size(2, c.maxHeight),
                  painter: _TicketDashDividerPainter(color: dividerColor),
                ),
              ),
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: stampBg,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(AppRadius.xl),
                  bottomRight: Radius.circular(AppRadius.xl),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                        Icon(Icons.qr_code_2, size: 38, color: qrColor),
                    const SizedBox(height: 6),
                        DefaultTextStyle.merge(
                          style: (Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 10)).copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                            height: 1.05,
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: CaddyMoneyWordmark(textAlign: TextAlign.center),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketDashDividerPainter extends CustomPainter {
  final Color color;

  const _TicketDashDividerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    const dash = 3.2;
    const gap = 3.2;
    double y = 0;
    final x = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + dash, size.height)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TicketDashDividerPainter oldDelegate) => oldDelegate.color != color;
}

class _TicketHole extends StatelessWidget {
  final Color color;
  final bool isOutlined;

  const _TicketHole({required this.color, this.isOutlined = false});

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isOutlined ? Border.all(color: Colors.white.withValues(alpha: 0.92), width: 1.4) : null,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.25),
              blurRadius: 0,
              spreadRadius: 0.6,
            ),
          ],
        ),
      );
}

class HomeOpenScannerButton extends StatelessWidget {
  const HomeOpenScannerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradientColors = isDark ? AppColors.balanceCardGradientDark : AppColors.balanceCardGradientLight;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        onTap: () {
          context.push(AppRoutes.qrScan);
        },
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: gradientColors),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.credit_card_rounded, color: Colors.white.withValues(alpha: 0.95)),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  (AppLocalizations.of(context)?.openScanner ?? 'Open scanner'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.92)),
            ],
          ),
        ),
      ),
    );
  }
}

class BalanceWithQrButton extends StatefulWidget {
  final double? balance;
  final String? currencyCode;
  final bool isLoading;
  final Future<void> Function() onTapQr;

  const BalanceWithQrButton({
    super.key,
    required this.balance,
    required this.currencyCode,
    required this.isLoading,
    required this.onTapQr,
  });

  @override
  State<BalanceWithQrButton> createState() => _BalanceWithQrButtonState();
}

class _BalanceWithQrButtonState extends State<BalanceWithQrButton> {
  late final ValueNotifier<int> _glowTick;

  @override
  void initState() {
    super.initState();
    _glowTick = ValueNotifier<int>(0);
  }

  @override
  void dispose() {
    _glowTick.dispose();
    super.dispose();
  }

  void _handleOrbitComplete() {
    // Incrementing the tick is enough to trigger a pulse on the QR button.
    _glowTick.value = _glowTick.value + 1;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the same balance circle, but add a floating circular QR button like the mock.
    return Center(
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: BalanceCard(
                balance: widget.balance,
                currencyCode: widget.currencyCode,
                isLoading: widget.isLoading,
                onOrbitComplete: _handleOrbitComplete,
              ),
            ),
            Positioned(
              right: -6,
              bottom: 28,
              child: QrCircleButton(onTap: widget.onTapQr, glowTick: _glowTick),
            ),
          ],
        ),
      ),
    );
  }
}

class QrCircleButton extends StatefulWidget {
  final Future<void> Function() onTap;
  final ValueListenable<int>? glowTick;

  const QrCircleButton({super.key, required this.onTap, this.glowTick});

  @override
  State<QrCircleButton> createState() => _QrCircleButtonState();
}

class _QrCircleButtonState extends State<QrCircleButton> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _glowController;
  late final Animation<double> _glowOpacity;
  int? _lastGlowTick;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  void initState() {
    super.initState();
    // Slightly longer pulse so the glow reads clearly (especially in light mode).
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 720));
    _glowOpacity = _glowController.drive(
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
        TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0).chain(CurveTween(curve: Curves.easeIn)), weight: 60),
      ]),
    );
    _attachGlowListener(old: null);
  }

  @override
  void didUpdateWidget(covariant QrCircleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.glowTick != widget.glowTick) _attachGlowListener(old: oldWidget.glowTick);
  }

  void _attachGlowListener({required ValueListenable<int>? old}) {
    old?.removeListener(_onGlowTick);
    widget.glowTick?.addListener(_onGlowTick);
    _lastGlowTick = widget.glowTick?.value;
  }

  void _onGlowTick() {
    final tick = widget.glowTick?.value;
    if (tick == null || tick == _lastGlowTick) return;
    _lastGlowTick = tick;
    if (!mounted) return;
    _glowController.forward(from: 0);
  }

  @override
  void dispose() {
    widget.glowTick?.removeListener(_onGlowTick);
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;

    return Semantics(
      button: true,
      label: 'Open QR scanner',
      child: GestureDetector(
        onTap: () async => widget.onTap(),
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          scale: _pressed ? 0.96 : 1.0,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Subtle eclipse-like glow pulse when the ring flash completes.
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, _) {
                      final t = _glowOpacity.value;
                      if (t <= 0.001) return const SizedBox.shrink();
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      // Requested: glow must be white (in both light + dark mode).
                      final glow = Colors.white;
                      final scale = lerpDouble(1.0, isDark ? 1.18 : 1.26, Curves.easeOut.transform(t)) ?? 1.0;
                      return Opacity(
                        opacity: t,
                        child: Transform.scale(
                          scale: scale,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: glow.withValues(alpha: isDark ? 0.46 : 0.62), width: isDark ? 2 : 2.4),
                              boxShadow: [
                                // Outer bloom.
                                BoxShadow(
                                  color: glow.withValues(alpha: isDark ? 0.32 : 0.44),
                                  blurRadius: isDark ? 34 : 44,
                                  spreadRadius: isDark ? 10 : 14,
                                ),
                                // Inner glow.
                                BoxShadow(
                                  color: glow.withValues(alpha: isDark ? 0.22 : 0.34),
                                  blurRadius: isDark ? 18 : 24,
                                  spreadRadius: isDark ? 4 : 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.65), width: 1.2),
                    boxShadow: [
                      // Always-on halo so the button reads well in light mode too.
                      BoxShadow(
                        color: Colors.white.withValues(alpha: isDark ? 0.26 : 0.44),
                        blurRadius: isDark ? 28 : 40,
                        spreadRadius: isDark ? 3 : 8,
                        offset: const Offset(0, 0),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.22),
                        blurRadius: isDark ? 14 : 18,
                        spreadRadius: 0,
                        offset: const Offset(0, 0),
                      ),
                      BoxShadow(
                        // Soft, premium depth.
                        color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.14),
                        blurRadius: 18,
                        spreadRadius: -6,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(Icons.qr_code_rounded, color: accent, size: 30),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePrimaryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const HomePrimaryActionButton({super.key, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.18),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class BalanceCard extends StatelessWidget {
  final double? balance;
  final String? currencyCode;
  final bool isLoading;
  final VoidCallback? onOrbitComplete;

  const BalanceCard({
    super.key,
    required this.balance,
    required this.currencyCode,
    required this.isLoading,
    this.onOrbitComplete,
  });

  static List<Color> _gradientColorsFor(BuildContext context) {
    // Visual-only tweak requested: the outer ring should be white (instead of the
    // previous green/accent sweep). We keep a subtle sweep by varying alpha.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Colors.white;
    // Slightly higher opacity in dark mode to maintain visibility.
    final strong = base.withValues(alpha: isDark ? 0.92 : 0.82);
    final soft = base.withValues(alpha: isDark ? 0.28 : 0.22);
    return <Color>[soft, strong, soft, strong];
  }

  static String _currencyPrefix(String? currencyCode) {
    switch (currencyCode) {
      case 'EUR':
        return '€';
      case 'USD':
        return r'$';
      case 'GBP':
        return '£';
      default:
        return currencyCode == null || currencyCode.trim().isEmpty ? '€' : '${currencyCode.trim()} ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefix = _currencyPrefix(currencyCode);
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseAmountStyle =
            (textTheme.displaySmall ?? textTheme.headlineLarge)?.copyWith(fontWeight: FontWeight.w900, height: 1.02) ??
        const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.02);

    // Visual tweak requested: make the currency symbol smaller and the numeric amount slightly larger.
    final prefixStyle = baseAmountStyle.copyWith(
      fontSize: (baseAmountStyle.fontSize ?? 40) * 0.68,
      height: 1.0,
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );
    final amountStyle = baseAmountStyle.copyWith(
      fontSize: (baseAmountStyle.fontSize ?? 40) * 1.08,
      color: Colors.white,
      fontWeight: FontWeight.w900,
    );

    // New concept: amount displayed inside a circle (as per provided UI concept).
    // We keep the same data/logic; only the layout changes.
    const size = 220.0;
    const ringRadius = (size / 2) - 6;

    // Align the flash's start/end point with the center of the QR button.
    // Note: BalanceWithQrButton positions the QR button at right:-6, bottom:28 with a 64x64 size.
    const qrButtonSize = 64.0;
    const qrRight = -6.0;
    const qrBottom = 28.0;
    final qrCenter = Offset(size - qrButtonSize - qrRight + (qrButtonSize / 2), size - qrButtonSize - qrBottom + (qrButtonSize / 2));
    const circleCenter = Offset(size / 2, size / 2);
    final v = qrCenter - circleCenter;
    final startAngleRad = math.atan2(v.dy, v.dx);
    return Center(
      child: SizedBox(
        height: size,
        width: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(size, size),
              painter: _CircleRingPainter(colors: _gradientColorsFor(context)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Subtle glassmorphism: a brighter translucent layer over the gradient.
                    color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.18),
                    border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.26), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.10),
                        blurRadius: 28,
                        spreadRadius: -14,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Total disponible',
                          style: textTheme.labelLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        if (isLoading)
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        else
                          Transform.translate(
                            offset: const Offset(0, -4),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: prefix, style: prefixStyle),
                                  TextSpan(text: (balance ?? 0).toStringAsFixed(2), style: amountStyle),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Sexy "flash" orbit around the ring.
            IgnorePointer(
              child: RingFlashOrbit(
                size: size,
                ringRadius: ringRadius,
                color: Colors.white,
                startAngleRad: startAngleRad,
                onLapComplete: onOrbitComplete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleRingPainter extends CustomPainter {
  final List<Color> colors;

  const _CircleRingPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 6;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(colors: colors, startAngle: -1.2, endAngle: 5.0);

    final ringPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    // Soft glow.
    final glowPaint = Paint()
      ..color = colors.last.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    canvas.drawCircle(center, radius, glowPaint);
    canvas.drawCircle(center, radius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _CircleRingPainter oldDelegate) => !listEquals(oldDelegate.colors, colors);
}

class BalanceBreakdownRow extends StatelessWidget {
  final bool isLoading;
  final double? totalReceived;
  final double? totalSpentAtMerchants;
  final String? currencyCode;

  const BalanceBreakdownRow({
    super.key,
    required this.isLoading,
    required this.totalReceived,
    required this.totalSpentAtMerchants,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prefix = BalanceCard._currencyPrefix(currencyCode);

    Widget metric({required String label, required String value, required Color accent}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.18),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Calculating totals…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final received = totalReceived ?? 0;
    final spent = totalSpentAtMerchants ?? 0;

    return Row(
      children: [
        metric(label: 'Total received', value: '+$prefix${received.toStringAsFixed(2)}', accent: AppColors.transactionReceived),
        const SizedBox(width: AppSpacing.md),
        metric(label: 'Total spent', value: '-$prefix${spent.toStringAsFixed(2)}', accent: AppColors.transactionSent),
      ],
    );
  }
}

class QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const QuickActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeRecentTransactionTile extends StatelessWidget {
  final TransactionModel transaction;

  const HomeRecentTransactionTile({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final uid = SupabaseConfig.auth.currentUser?.id;
    final isIncoming = uid != null && transaction.receiverProfileId == uid;
    final isCredit = isIncoming;
    final amountColor = isCredit ? AppColors.transactionReceived : AppColors.transactionSent;
    final primary = _primaryLineFor(transaction);
    final secondary = _secondaryLineFor(transaction, isCredit: isCredit);
    
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Center(
              child: Text(
                isCredit ? '+' : '-',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: amountColor, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  secondary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}${transaction.amount.abs().toStringAsFixed(2)}€',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static String _primaryLineFor(TransactionModel t) {
    final category = _transferCategory(t);
    if (category != null && category.isNotEmpty) return category;
    return _fallbackTitleFor(t);
  }

  static String _secondaryLineFor(TransactionModel t, {required bool isCredit}) {
    final date = _formatTime(t.createdAt);
    final counterparty = _counterpartyNameFor(t, isCredit: isCredit);
    if (counterparty.isEmpty) return date;
    return '$date • $counterparty';
  }

  static String _counterpartyNameFor(TransactionModel t, {required bool isCredit}) {
    if (t.type == TransactionType.userToUser) {
      if (isCredit) return (t.senderFullName ?? '').trim();
      return (t.receiverFullName ?? '').trim();
    }

    if (t.type == TransactionType.userToMerchant) return (t.receiverMerchantBusinessName ?? '').trim();
    return '';
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
}
