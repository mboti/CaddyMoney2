import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/providers/language_provider.dart';
import 'package:caddymoney/services/wallet_service.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/core/constants/app_constants.dart';
import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/screens/merchant/widgets/merchant_identity_card.dart';
import 'package:caddymoney/screens/merchant/widgets/merchant_status_badge.dart';
import 'package:caddymoney/screens/user/widgets/user_bottom_nav_bar.dart';
import 'package:caddymoney/core/enums/app_role.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';
import 'package:caddymoney/screens/support/support_center_screen.dart';
import 'package:caddymoney/services/support_request_service.dart';

class SettingsScreen extends StatelessWidget {
  final bool? showAppBarLeading;
  final Widget? bottomNavigationBarOverride;

  const SettingsScreen({super.key, this.showAppBarLeading, this.bottomNavigationBarOverride});

  Future<void> _claimTestTopUp(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await WalletService().claimTestTopUp(amount: 1000);
    final ok = res['success'] == true;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? 'Wallet credited: €1000' : (res['error']?.toString() ?? 'Top up failed'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = context.watch<AuthProvider>();
    final languageProvider = context.watch<LanguageProvider>();
    final user = authProvider.currentUser;
    final merchant = authProvider.currentMerchant;

    final hasBottomNav = bottomNavigationBarOverride != null || user?.role == AppRole.standardUser;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    // Our custom bottom nav bars (user + merchant) are taller than
    // `kBottomNavigationBarHeight` due to internal padding.
    // Add extra spacing so the last action (e.g., “Sign out”) can scroll fully
    // above the bar when `extendBody: true`.
    final bottomScrollPadding = hasBottomNav
        ? (kBottomNavigationBarHeight + bottomInset + AppSpacing.xl + AppSpacing.md)
        : AppSpacing.lg;

    final merchantId = merchant?.uniqueMerchantId ?? '—';
    final businessName = merchant?.businessName ?? (user?.fullName ?? 'Business');
    final categoryLabel = (merchant?.categories ?? const <String>[]).isNotEmpty
        ? merchant!.categories.join(', ')
        : (merchant?.businessCategory ?? '—');

    return Scaffold(
      extendBody: true,
      appBar: CaddyMoneyTopAppBar(
        showLeading: showAppBarLeading ?? (authProvider.userRole != AppRole.standardUser),
      ),
      // Always show the user bottom nav inside the standard user area.
      // Using `currentUser.role` avoids any transient null role during startup.
      bottomNavigationBar: bottomNavigationBarOverride ?? (user?.role == AppRole.standardUser ? const UserBottomNavBar() : null),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: AppSpacing.paddingLg.copyWith(bottom: bottomScrollPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.center,
                child: Text(
                  l10n.settings,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (user != null) ...[
                Text(
                  'Account',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: AppSpacing.paddingMd,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Text(
                              user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.fullName,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  user.email,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(AppRadius.sm),
                                      ),
                                      child: Text(
                                        user.role.displayName,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (merchant != null) MerchantStatusBadge(merchantStatus: merchant.status),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              if (merchant != null) ...[
                Text(
                  'Merchant',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                MerchantIdentityCard(
                  merchantId: merchantId,
                  businessName: businessName,
                  category: categoryLabel,
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              Text(
                'Payments',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsTile(
                icon: Icons.credit_card,
                title: 'Payment methods',
                subtitle: 'Add and manage your bank cards',
                onTap: () => context.push('/payment-methods'),
              ),
              if (kDebugMode && user != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _SettingsTile(
                  icon: Icons.bolt,
                  title: 'Test top up (dev)',
                  subtitle: 'Credit €1000 once to test transfers',
                  onTap: () => _claimTestTopUp(context),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Preferences',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: AppSpacing.paddingMd,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.language,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    DropdownButton<String>(
                      value: languageProvider.languageCode,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem(value: 'fr', child: Text('Français')),
                        const DropdownMenuItem(value: 'en', child: Text('English')),
                        const DropdownMenuItem(value: 'es', child: Text('Español')),
                        const DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                        const DropdownMenuItem(value: 'it', child: Text('Italiano')),
                        const DropdownMenuItem(value: 'ar', child: Text('العربية')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          languageProvider.setLanguage(value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Support',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsTile(
                icon: Icons.support_agent,
                title: 'Support request',
                subtitle: 'Report an issue and get a ticket number',
                onTap: () async {
                  final type = merchant != null ? SupportRequesterType.merchant : SupportRequesterType.user;
                  await SupportRequestService().markAllMyAdminResponsesSeen(requesterType: type);
                  if (!context.mounted) return;
                  context.push(AppRoutes.supportCenter, extra: SupportCenterArgs(requesterType: type, initialTabIndex: 0));
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'About',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: AppSpacing.paddingMd,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.version,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    Text(
                      '1.0.0',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        highlightColor: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            border: Border.all(color: cs.outline),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
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
