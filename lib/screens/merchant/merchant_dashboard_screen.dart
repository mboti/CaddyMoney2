import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/core/constants/app_constants.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/models/payment_intent_model.dart';
import 'package:caddymoney/services/payment_intent_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caddymoney/screens/merchant/widgets/merchant_bottom_nav_bar.dart';
import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/core/utils/transaction_reference.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';
import 'package:caddymoney/widgets/support_notifications_app_bar.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';

class MerchantDashboardScreen extends StatefulWidget {
  const MerchantDashboardScreen({super.key});

  @override
  State<MerchantDashboardScreen> createState() => _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState extends State<MerchantDashboardScreen> {
  void _onQrSheetClosed() {}

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final merchant = authProvider.currentMerchant;

    final businessName = merchant?.businessName ?? (user?.fullName ?? 'Business');
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      extendBody: true,
      appBar: const SupportNotificationsAppBar(showLeading: false, requesterType: SupportRequesterType.merchant),
      bottomNavigationBar: const MerchantBottomNavBar(),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            const Positioned.fill(child: MerchantHomeBackground()),
            _MerchantHomeBody(
              businessName: businessName,
              logoPathOrUrl: merchant?.logoPath,
              keyboardOpen: keyboardOpen,
              onSheetClosed: _onQrSheetClosed,
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantHomeBody extends StatelessWidget {
  final String businessName;
  final String? logoPathOrUrl;
  final bool keyboardOpen;
  final VoidCallback onSheetClosed;

  const _MerchantHomeBody({
    required this.businessName,
    required this.logoPathOrUrl,
    required this.keyboardOpen,
    required this.onSheetClosed,
  });

  @override
  Widget build(BuildContext context) {
    // NOTE: This screen uses `extendBody: true` + a bottom nav.
    // On smaller devices, the fixed-height amount card can overflow vertically.
    // Always allowing vertical scrolling avoids RenderFlex overflows while still
    // feeling like a dashboard (content is short; scrolling is minimal).
    final bottomNavGuard = MediaQuery.paddingOf(context).bottom + kBottomNavigationBarHeight;
    final padding = EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottomNavGuard);
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          MerchantHomeHeader(logoPathOrUrl: logoPathOrUrl, businessName: businessName),
          const SizedBox(height: AppSpacing.xl),
          MerchantAmountEntrySpace(onSheetClosed: onSheetClosed),
        ],
      ),
    );

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, overscroll: false),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: keyboardOpen ? const ClampingScrollPhysics() : const ClampingScrollPhysics(),
        child: content,
      ),
    );
  }
}

class MerchantHomeHeader extends StatelessWidget {
  final String? logoPathOrUrl;
  final String businessName;

  const MerchantHomeHeader({super.key, required this.logoPathOrUrl, required this.businessName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.merchantHomeCardDark : cs.surface;
    final outline = isDark ? cs.outline.withValues(alpha: 0.25) : cs.outline.withValues(alpha: 0.18);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MerchantLogoCircle(logoPathOrUrl: logoPathOrUrl, size: 72),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Paiement rapide & sécurisé',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MerchantHomeBackground extends StatelessWidget {
  const MerchantHomeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Per mock: solid background (no gradient / glow).
    final bg = isDark ? AppColors.merchantHomeBackgroundDark : Theme.of(context).colorScheme.background;
    return ColoredBox(color: bg);
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)], stops: const [0, 1]),
        ),
      ),
    );
  }
}

class MerchantLogoCircle extends StatelessWidget {
  final String? logoPathOrUrl;
  final double size;

  const MerchantLogoCircle({
    super.key,
    required this.logoPathOrUrl,
    this.size = 44,
  });

  /// In-memory cache to avoid re-requesting signed URLs while scrolling lists.
  ///
  /// Key = normalized object path (without bucket), value = Future resolving to a URL.
  static final Map<String, Future<String?>> _signedUrlCache = <String, Future<String?>>{};

  bool _isHttpUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  bool _looksLikeSupabaseStorageUrl(String s) => s.contains('/storage/v1/object/');

  /// Attempts to extract the storage object path from a Supabase Storage URL.
  ///
  /// Examples we handle:
  /// - https://<project>.supabase.co/storage/v1/object/public/<bucket>/<path>
  /// - https://<project>.supabase.co/storage/v1/object/sign/<bucket>/<path>?token=...
  ///
  /// Returns the object key/path *without* the bucket prefix (e.g. `merchant/<uid>/logo/x.png`).
  String? _extractObjectPathFromStorageUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final idx = segments.indexWhere((s) => s == 'object');
      if (idx == -1) return null;

      // Expect: .../object/(public|sign)/<bucket>/<object...>
      if (segments.length < idx + 3) return null;
      final mode = segments[idx + 1];
      if (mode != 'public' && mode != 'sign') return null;
      // bucket currently unused, but parsing it validates the URL shape.
      final _bucket = segments[idx + 2];
      if (_bucket.trim().isEmpty) return null;

      final objectStart = idx + 3;
      if (segments.length <= objectStart) return null;
      final objectPath = segments.sublist(objectStart).join('/');
      if (objectPath.trim().isEmpty) return null;

      final bucketPrefix = '${AppConstants.kycStorageBucket}/';
      // If the URL bucket isn't our expected one, we still return the objectPath,
      // because callers always specify the bucket separately.
      if (objectPath.startsWith(bucketPrefix)) return objectPath.substring(bucketPrefix.length);
      return objectPath;
    } catch (_) {
      return null;
    }
  }

  String _normalizeObjectPath(String raw) {
    var p = raw.trim();
    if (p.startsWith('/')) p = p.substring(1);

    // If stored as a full Supabase Storage URL (public/sign), extract the object path.
    if (_isHttpUrl(p) && _looksLikeSupabaseStorageUrl(p)) {
      final extracted = _extractObjectPathFromStorageUrl(p);
      if (extracted != null) p = extracted;
    }

    // If accidentally stored as "bucket/path", keep only the object path.
    final bucketPrefix = '${AppConstants.kycStorageBucket}/';
    if (p.startsWith(bucketPrefix)) p = p.substring(bucketPrefix.length);

    // If stored as a storage API URL, attempt to extract the object path.
    final marker = '/object/';
    final idx = p.indexOf(marker);
    if (idx != -1) {
      final after = p.substring(idx + marker.length);
      // Usually "bucket/path".
      if (after.startsWith(bucketPrefix)) return after.substring(bucketPrefix.length);
      final slash = after.indexOf('/');
      if (slash != -1) {
        var maybeBucketAndPath = after.substring(slash + 1);
        // Ensure we strip the bucket prefix if it exists after extraction.
        if (maybeBucketAndPath.startsWith(bucketPrefix)) maybeBucketAndPath = maybeBucketAndPath.substring(bucketPrefix.length);
        return maybeBucketAndPath;
      }
    }
    return p;
  }

  Future<String?> _resolveUrl() async {
    final raw = logoPathOrUrl;
    if (raw == null || raw.trim().isEmpty) return null;

    // If a full Supabase Storage URL was persisted, re-sign it so it doesn't expire.
    if (_isHttpUrl(raw) && !_looksLikeSupabaseStorageUrl(raw)) return raw;

    final normalized = _normalizeObjectPath(raw);

    // If the logo is stored in a private bucket (KYC) and is a merchant logo path,
    // directly ask the Edge Function to mint a signed URL (service role), because
    // client-side signing often returns 404 even when the object exists.
    if (normalized.startsWith('merchant/')) {
      return _signedUrlCache.putIfAbsent(normalized, () async {
        try {
          final res = await SupabaseConfig.client.functions.invoke(
            'merchant_logo_signed_url',
            body: {
              'bucket': AppConstants.kycStorageBucket,
              'object_path': normalized,
              'expires_in': 60 * 15,
            },
          );
          final data = res.data;
          final url = (data is Map) ? (data['url']?.toString()) : null;
          if (url != null && url.trim().isNotEmpty) return url;
          debugPrint('MerchantLogoCircle: edge function returned no url (raw="$raw" normalized="$normalized") status=${res.status} data=$data');
        } catch (ef) {
          debugPrint('MerchantLogoCircle: edge-function signed url failed (raw="$raw" normalized="$normalized"): $ef');
        }

        // Fallback: if bucket is public (or becomes public later), this still works.
        try {
          final publicUrl = SupabaseConfig.client.storage.from(AppConstants.kycStorageBucket).getPublicUrl(normalized);
          if (publicUrl.trim().isNotEmpty) return publicUrl;
        } catch (e2) {
          debugPrint('MerchantLogoCircle: failed to resolve public logo url: $e2');
        }
        return null;
      });
    }

    // Otherwise, do a normal signed URL attempt.
    try {
      final signed = await SupabaseConfig.client.storage
          .from(AppConstants.kycStorageBucket)
          .createSignedUrl(normalized, 60 * 15);
      return signed;
    } on StorageException catch (e) {
      debugPrint('MerchantLogoCircle: failed to sign logo url (raw="$raw" normalized="$normalized"): $e');
      try {
        final publicUrl = SupabaseConfig.client.storage.from(AppConstants.kycStorageBucket).getPublicUrl(normalized);
        if (publicUrl.trim().isNotEmpty) return publicUrl;
      } catch (e2) {
        debugPrint('MerchantLogoCircle: failed to resolve public logo url: $e2');
      }
      return null;
    } catch (e) {
      debugPrint('MerchantLogoCircle: failed to resolve logo url (raw="$raw" normalized="$normalized"): $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<String?>(
      future: _resolveUrl(),
      builder: (context, snapshot) {
        final url = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
            border: Border.all(color: cs.outline.withValues(alpha: 0.6)),
          ),
          child: ClipOval(
            child: url == null
                ? Center(
                    child: isLoading
                        ? SizedBox(
                            width: size * 0.42,
                            height: size * 0.42,
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurfaceVariant),
                          )
                        : Icon(Icons.storefront_outlined, color: cs.onSurfaceVariant),
                  )
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Center(
                      child: Icon(Icons.storefront_outlined, color: cs.onSurfaceVariant),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// Reserved area on the merchant dashboard for entering the payable amount.
///
/// We keep this spacing intentionally (per UI spec) so we can later place an
/// amount input + actions here without reflowing the rest of the dashboard.
class MerchantAmountEntrySpace extends StatefulWidget {
  final VoidCallback? onSheetClosed;

  const MerchantAmountEntrySpace({super.key, this.onSheetClosed});

  // IMPORTANT: This card must be tall enough for:
  // padding + label + spacing + amount field + spacing + CTA button.
  // If it's too short, the Expanded area will squeeze the input, and large
  // glyphs (like "0,00") get clipped at the bottom.
  static const double height = 360;

  @override
  State<MerchantAmountEntrySpace> createState() => _MerchantAmountEntrySpaceState();
}

class _MerchantAmountEntrySpaceState extends State<MerchantAmountEntrySpace> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isSubmitting = false;

  void _resetAmountToZero() {
    if (!mounted) return;
    _controller
      ..text = '0'
      ..selection = const TextSelection.collapsed(offset: 1);
    // Also ensure the field is no longer focused (keyboard dismissed).
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode()
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseAmountStyle = Theme.of(context).textTheme.displaySmall;
    final amountFontSize = ((baseAmountStyle?.fontSize ?? 34) * 1.85).clamp(52, 88).toDouble();
    // Don't force a custom `TextStyle.height` here.
    // On some platforms it can lead to baseline/strut mismatches inside TextField,
    // which shows up as bottom-clipping with very large fonts.
    final amountStyle = baseAmountStyle?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: cs.onSurface,
          fontSize: amountFontSize,
        ) ??
        TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: cs.onSurface,
          fontSize: amountFontSize,
        );

    return MerchantAmountCard(
      focusNode: _focusNode,
      controller: _controller,
      amountStyle: amountStyle,
      isSubmitting: _isSubmitting,
      onGenerateQrPressed: _isSubmitting ? null : () => _onGenerateQrPressed(context),
    );
  }

  double? _parseAmount() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return null;
    // Allow both "12.34" and "12,34".
    final normalized = raw.replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null || value <= 0) return null;
    return value;
  }

  Future<void> _onGenerateQrPressed(BuildContext context) async {
    final amount = _parseAmount();
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount first.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (!context.mounted) return;

      // Dismiss the numeric keyboard while the QR sheet is open.
      // (And ensures it won't remain open if the sheet auto-closes quickly.)
      FocusManager.instance.primaryFocus?.unfocus();

      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _PaymentIntentQrSheet(
          amount: amount,
          currencyCode: 'EUR',
          onPaymentCompleted: _resetAmountToZero,
        ),
      );

      // Refresh the dashboard (recent payments + totals) after the sheet closes.
      // This covers both auto-close after successful payment and manual close.
      widget.onSheetClosed?.call();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class MerchantAmountCard extends StatelessWidget {
  final FocusNode focusNode;
  final TextEditingController controller;
  final TextStyle amountStyle;
  final bool isSubmitting;
  final VoidCallback? onGenerateQrPressed;

  const MerchantAmountCard({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.amountStyle,
    required this.isSubmitting,
    required this.onGenerateQrPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Match mock: darker card + subtle teal border.
    final baseCardBg = isDark ? AppColors.merchantHomeCardDark : cs.surface;
    final focusedCardBg = isDark ? AppColors.merchantHomeAmountCardFocusedDark : cs.surface;
    final cardBg = focusNode.hasFocus ? focusedCardBg : baseCardBg;
    final outline = isDark ? cs.primary.withValues(alpha: 0.35) : cs.outline.withValues(alpha: 0.55);
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700);
    final currencyStyle = Theme.of(context).textTheme.titleLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800, letterSpacing: -0.2);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: MerchantAmountEntrySpace.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: outline),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: () => focusNode.requestFocus(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Montant à payer', style: labelStyle),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: SizedBox(
                              // Taller input area to match the mock (big amount, generous vertical space).
                              // NOTE: Keep this <= available Expanded height inside the card.
                              height: 176,
                              child: TextField(
                                controller: controller,
                                focusNode: focusNode,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.center,
                                textAlignVertical: TextAlignVertical.center,
                                maxLines: 1,
                                style: amountStyle,
                                // Force a stable, generous line box across platforms.
                                // This prevents the bottom of large digits/comma from being clipped.
                                strutStyle: StrutStyle(
                                  fontSize: amountStyle.fontSize,
                                  height: 1.25,
                                  forceStrutHeight: true,
                                ),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                                decoration: InputDecoration(
                                  hintText: focusNode.hasFocus ? null : '0,00',
                                  // Match mock: the input area should blend into the card (no inner box).
                                  filled: true,
                                  fillColor: cardBg,
                                  border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(16)),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(16)),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(16)),
                                  disabledBorder: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(16)),
                                  // Provide explicit vertical breathing room so the baseline can't sit too low.
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 28),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Text('EUR', style: currencyStyle),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _GenerateQrWideButton(isLoading: isSubmitting, onPressed: onGenerateQrPressed),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GenerateQrWideButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _GenerateQrWideButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = onPressed != null;
    final radius = BorderRadius.circular(22);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: isEnabled ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          borderRadius: radius,
          child: Ink(
            height: 64,
            decoration: BoxDecoration(color: cs.primary, borderRadius: radius),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: isLoading
                    ? SizedBox(
                        key: const ValueKey('loading'),
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.7, color: cs.onPrimary),
                      )
                    : Row(
                        key: const ValueKey('content'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_2, color: cs.onPrimary),
                          const SizedBox(width: 12),
                          Text(
                            'GENERER LE QR CODE',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w900, letterSpacing: 0.2),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GenerateQrPillButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _GenerateQrPillButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = onPressed != null;
    final radius = BorderRadius.circular(20);
    // Match mock: solid teal button (no gradient).
    final bg = cs.primary;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: isEnabled ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          borderRadius: radius,
          child: Ink(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: bg, borderRadius: radius),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: isLoading
                    ? SizedBox(
                        key: const ValueKey('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
                      )
                    : Column(
                        key: const ValueKey('icon'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_2, color: cs.onPrimary),
                          const SizedBox(height: 2),
                          Text('QR CODE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _GenerateQrButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _GenerateQrButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // Replaced by _GenerateQrPillButton in the redesigned MerchantAmountCard.
    // Keeping this widget for backward compatibility (unused).
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isLoading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
                )
              : const Icon(Icons.qr_code_2, key: ValueKey('icon')),
        ),
      ),
    );
  }
}

enum _PaymentIntentQrSheetState { loading, success, error, expired }

class _PaymentIntentQrSheet extends StatefulWidget {
  final double amount;
  final String currencyCode;
  final VoidCallback? onPaymentCompleted;

  const _PaymentIntentQrSheet({required this.amount, required this.currencyCode, this.onPaymentCompleted});

  @override
  State<_PaymentIntentQrSheet> createState() => _PaymentIntentQrSheetStateful();
}

class _PaymentIntentQrSheetStateful extends State<_PaymentIntentQrSheet> {
  final _service = PaymentIntentService();
  _PaymentIntentQrSheetState _state = _PaymentIntentQrSheetState.loading;
  PaymentIntentModel? _intent;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _state = _PaymentIntentQrSheetState.loading;
      _intent = null;
      _error = null;
    });

    final res = await _service.createPaymentIntent(amount: widget.amount, currencyCode: widget.currencyCode);
    if (!mounted) return;

    if (res.intent == null) {
      setState(() {
        _state = _PaymentIntentQrSheetState.error;
        _error = res.error ?? 'Request failed.';
      });
      return;
    }

    final intent = res.intent!;
    setState(() {
      _intent = intent;
      _state = intent.isExpired ? _PaymentIntentQrSheetState.expired : _PaymentIntentQrSheetState.success;
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final i = _intent;
      if (i == null) return;
      if (DateTime.now().isAfter(i.expiresAt)) {
        setState(() => _state = _PaymentIntentQrSheetState.expired);
      } else {
        // Tick to update countdown label.
        setState(() {});
      }
    });
  }

  Future<void> _signInAgain() async {
    try {
      // Clear any stale session and send the merchant back to auth.
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('Sign out failed during re-auth: $e');
    }
    if (!mounted) return;
    context.go(AppRoutes.merchantAuth);
  }

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
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: switch (_state) {
                _PaymentIntentQrSheetState.loading => const _QrSheetLoading(key: ValueKey('loading')),
                _PaymentIntentQrSheetState.error => _QrSheetError(
                    key: const ValueKey('error'),
                    message: _error ?? 'Request failed.',
                    onRetry: _create,
                    onSignInAgain: _signInAgain,
                  ),
                _PaymentIntentQrSheetState.expired => _QrSheetExpired(
                    key: const ValueKey('expired'),
                    onRegenerate: _create,
                  ),
                _PaymentIntentQrSheetState.success => _QrSheetSuccess(
                    key: const ValueKey('success'),
                    intent: _intent!,
                    amount: widget.amount,
                    currencyCode: widget.currencyCode,
                    onRegenerate: _create,
                    onPaymentCompleted: widget.onPaymentCompleted,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _QrSheetHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _QrSheetHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.qr_code_2, color: cs.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.close, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _QrSheetLoading extends StatelessWidget {
  const _QrSheetLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _QrSheetHeader(title: 'Generating QR code', subtitle: 'Creating a secure payment request…'),
        const SizedBox(height: AppSpacing.lg),
        Center(child: CircularProgressIndicator(color: cs.primary)),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _QrSheetError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignInAgain;

  const _QrSheetError({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onSignInAgain,
  });

  bool get _isAuthError => message.toLowerCase().contains('unauthorized') || message.toLowerCase().contains('sign in');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _QrSheetHeader(title: 'Could not generate QR', subtitle: 'Please try again.'),
        const SizedBox(height: AppSpacing.md),
        Container(
          width: double.infinity,
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: cs.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: cs.error.withValues(alpha: 0.35)),
          ),
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.error)),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: _isAuthError
              ? FilledButton.icon(
                  onPressed: onSignInAgain,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in again'),
                )
              : FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
        ),
      ],
    );
  }
}

class _QrSheetExpired extends StatelessWidget {
  final VoidCallback onRegenerate;

  const _QrSheetExpired({super.key, required this.onRegenerate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _QrSheetHeader(title: 'QR expired', subtitle: 'Payment request is no longer valid.'),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Generate a new QR code to request payment again.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onRegenerate,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Generate new QR'),
          ),
        ),
      ],
    );
  }
}

class _QrSheetSuccess extends StatefulWidget {
  final PaymentIntentModel intent;
  final double amount;
  final String currencyCode;
  final VoidCallback onRegenerate;
  final VoidCallback? onPaymentCompleted;

  const _QrSheetSuccess({
    super.key,
    required this.intent,
    required this.amount,
    required this.currencyCode,
    required this.onRegenerate,
    this.onPaymentCompleted,
  });

  @override
  State<_QrSheetSuccess> createState() => _QrSheetSuccessState();
}

class _QrSheetSuccessState extends State<_QrSheetSuccess> {
  final _service = PaymentIntentService();
  late final Stream<PaymentIntentModel> _intentStream;
  StreamSubscription<PaymentIntentModel>? _realtimeSub;
  Timer? _pollTimer;
  bool _didHandlePayment = false;
  late final StreamController<PaymentIntentModel> _mergedController;

  @override
  void initState() {
    super.initState();
    final id = widget.intent.id;

    _mergedController = StreamController<PaymentIntentModel>.broadcast();

    _intentStream = SupabaseConfig.client
        .from('payment_intents')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) {
          if (rows.isEmpty) return widget.intent;
          final m = rows.first;
          if (m is Map) return PaymentIntentModel.fromJson(Map<String, dynamic>.from(m));
          return widget.intent;
        });

    // 1) Realtime (best case)
    _realtimeSub = _intentStream.listen(
      (intent) => _mergedController.add(intent),
      onError: (e) => debugPrint('Merchant QR sheet realtime stream error: $e'),
    );

    // 2) Polling fallback (reliable even if realtime isn\'t configured)
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final latest = await _service.getPaymentIntentById(id);
      if (!mounted) return;
      if (latest != null) _mergedController.add(latest);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _realtimeSub?.cancel();
    _mergedController.close();
    super.dispose();
  }

  String _formatRemaining(PaymentIntentModel intent) {
    final now = DateTime.now();
    final diff = intent.expiresAt.difference(now);
    if (diff.isNegative) return '00:00';
    final totalSeconds = diff.inSeconds;
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<PaymentIntentModel>(
      stream: _mergedController.stream,
      initialData: widget.intent,
      builder: (context, snapshot) {
        final intent = snapshot.data ?? widget.intent;
        final status = (intent.status).toLowerCase();
        final isPaid = status == 'completed' || status == 'paid' || status == 'succeeded';
        final isExpired = status == 'expired' || intent.isExpired;
        final remaining = _formatRemaining(intent);

        // IMPORTANT (merchant UX): do NOT auto-dismiss this sheet when payment is received.
        // The merchant should close it manually (via the X button) after reviewing.
        // We still run the completion callback once to reset the amount field, etc.
        if (isPaid && !_didHandlePayment) {
          _didHandlePayment = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            debugPrint('Merchant QR sheet: payment intent ${intent.id} marked paid (status=${intent.status}). Keeping sheet open for manual close.');
            widget.onPaymentCompleted?.call();
            FocusManager.instance.primaryFocus?.unfocus();
          });
        }

        if (isPaid) {
          return Column(
            key: widget.key,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _QrSheetHeader(title: 'Payment received', subtitle: 'Review the details, then close this popup manually.'),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified_outlined, color: cs.onTertiaryContainer),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.amount.toStringAsFixed(2)} ${widget.currencyCode}',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: cs.onTertiaryContainer),
                          ),
                          if ((intent.transactionReference ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Txn: ${shortenTransactionReference(intent.transactionReference!)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onTertiaryContainer.withValues(alpha: 0.9)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          key: widget.key,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _QrSheetHeader(title: 'QR ready', subtitle: 'Ask the customer to scan to pay.'),
            const SizedBox(height: AppSpacing.md),
            if (isExpired)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer_off_outlined, color: cs.onErrorContainer),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text('This request expired.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer))),
                  ],
                ),
              ),
            if (isExpired) const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: AppSpacing.paddingMd,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: cs.outline.withValues(alpha: 0.55)),
              ),
              child: Column(
                children: [
                  Text(
                    '${widget.amount.toStringAsFixed(2)} ${widget.currencyCode}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: (intent.shortCode != null && intent.shortCode!.trim().isNotEmpty) ? intent.shortCode!.trim() : intent.token,
                        version: QrVersions.auto,
                        size: 220,
                        gapless: false,
                        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: cs.onSurface),
                        dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: cs.onSurface),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer_outlined, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text('Expires in $remaining', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (intent.shortCode != null && intent.shortCode!.trim().isNotEmpty)
                    Text(
                      'Code: ${_formatTypingCode(intent.shortCode!)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    )
                  else
                    Text(
                      'Scan the QR to pay',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onRegenerate,
                icon: const Icon(Icons.refresh),
                label: const Text('Regenerate'),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _formatTypingCode(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  // For human typing, group in chunks of 4: ABCD-EFGH-....
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i != 0 && i % 4 == 0) buf.write('-');
    buf.write(s[i]);
  }
  return buf.toString();
}


