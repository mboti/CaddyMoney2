import 'dart:async';
import 'dart:convert';

import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/screens/user/widgets/user_bottom_nav_bar.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);

  bool _isProcessing = false;
  DateTime? _lastScanAt;

  @override
  void dispose() {
    // On web, mobile_scanner can throw MissingPluginException in Dreamflow preview.
    // Disposing defensively prevents noisy errors.
    try {
      _controller.dispose();
    } catch (e) {
      debugPrint('QrScanScreen.dispose: failed to dispose scanner controller: $e');
    }
    super.dispose();
  }

  Future<void> _handleRawCode(String raw, {bool bypassProcessingGuard = false}) async {
    debugPrint('QrScanScreen._handleRawCode: rawLen=${raw.length} rawPreview=${_redact(raw)}');
    final cleaned = _extractTokenOrId(raw);
    debugPrint('QrScanScreen._handleRawCode: extracted=${cleaned == null ? 'null' : 'len=${cleaned.length} preview=${_redact(cleaned)}'}');
    if (cleaned == null) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n?.invalidQr ?? 'Invalid QR code')));
      return;
    }

    final now = DateTime.now();
    if (_lastScanAt != null && now.difference(_lastScanAt!) < const Duration(milliseconds: 900)) return;
    _lastScanAt = now;

    // For camera scanning we need a strict guard to avoid rapid duplicate triggers.
    // For image-based scanning we may already be in a "processing" state (spinner
    // is shown while decoding bytes), so allow bypassing this guard.
    if (_isProcessing && !bypassProcessingGuard) return;

    if (!_isProcessing) {
      setState(() => _isProcessing = true);
    }

    try {
      if (!mounted) return;
      debugPrint('QrScanScreen._handleRawCode: navigating -> ${AppRoutes.qrPaymentConfirm}');
      final res = await context.push<bool>(
        AppRoutes.qrPaymentConfirm,
        extra: QrPaymentConfirmArgs(tokenOrId: cleaned),
      );
      debugPrint('QrScanScreen._handleRawCode: context.push returned res=$res');

      // If a payment was completed in the confirmation screen, propagate this
      // result back to the caller (typically Home) so it can refresh totals.
      if (res == true && context.mounted) context.pop(true);
    } catch (e) {
      debugPrint('QrScanScreen._handleRawCode: navigation failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to open confirmation screen')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  static String _redact(String s) {
    final t = s.trim();
    if (t.isEmpty) return '<empty>';

    // Don’t ever print full QR payloads/tokens; show only a small preview.
    final prefix = t.length <= 4 ? t : t.substring(0, 4);
    final suffix = t.length <= 4 ? '' : t.substring(t.length - 4);
    final ascii = utf8.encode(t).every((b) => b >= 32 && b <= 126);
    return '{ascii:$ascii, $prefix…$suffix}';
  }

  static String? _extractTokenOrId(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    // Accept a naked token/uuid.
    if (!s.contains('://') && !s.contains('?') && s.length >= 8) return s;

    // Accept deep-links/urls: ...?token=... or ...?payment_intent_id=...
    try {
      final uri = Uri.tryParse(s);
      if (uri != null) {
        final token = uri.queryParameters['token'] ?? uri.queryParameters['t'] ?? uri.queryParameters['payment_token'];
        if (token != null && token.trim().isNotEmpty) return token.trim();
        final id = uri.queryParameters['payment_intent_id'] ?? uri.queryParameters['id'];
        if (id != null && id.trim().isNotEmpty) return id.trim();
      }
    } catch (_) {}

    // Fallback: try to locate token_or_id=...
    final m = RegExp(r'(token_or_id|token|payment_intent_id)=([^&\s]+)', caseSensitive: false).firstMatch(s);
    final v = m?.group(2);
    if (v != null && v.trim().isNotEmpty) return v.trim();

    return null;
  }

  Future<void> _showManualEntrySheet() async {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n?.enterCode ?? 'Enter code', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: controller,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(hintText: 'token / id'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.pop(),
                            child: Text(l10n?.cancel ?? 'Cancel'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final v = controller.text.trim();
                              context.pop();
                              if (v.isNotEmpty) _handleRawCode(v);
                            },
                            child: Text(l10n?.confirm ?? 'Confirm'),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      // Don't render content behind the persistent bottom navigation.
      // This keeps the action buttons accessible on smaller screens.
      extendBody: false,
      appBar: const CaddyMoneyTopAppBar(),
      bottomNavigationBar: const UserBottomNavBar(),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  l10n?.scanQrCode ?? 'Scan a QR Code',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _QrScannerPanel(controller: _controller, isProcessing: _isProcessing, onRawCode: _handleRawCode)),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _showManualEntrySheet,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: Text(l10n?.enterCode ?? 'Enter code'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrScannerPanel extends StatelessWidget {
  const _QrScannerPanel({required this.controller, required this.isProcessing, required this.onRawCode});

  final MobileScannerController controller;
  final bool isProcessing;
  final Future<void> Function(String raw) onRawCode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Dreamflow runs a Flutter web preview; many camera scanner plugins rely on
    // native/mobile implementations and may not be available.
    if (kIsWeb) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner, color: cs.onSurfaceVariant, size: 44),
                    ],
                  ),
                ),
              ),
            ),
            if (isProcessing)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(24)),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                final first = capture.barcodes.where((b) => (b.rawValue ?? '').trim().isNotEmpty).map((b) => b.rawValue!).firstOrNull;
                if (first != null) unawaited(onRawCode(first));
              },
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.75), width: 2),
                      color: cs.primary.withValues(alpha: 0.04),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isProcessing)
          Positioned.fill(
            child: Container(
              color: cs.surface.withValues(alpha: 0.55),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
