import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/core/enums/app_role.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/nav.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  Future<void> _confirmSignOutAndGo(String route) async {
    final should = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.swap_horiz, color: cs.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Switch mode',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'To log in as a different role, you need to sign out from the current account first.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => context.pop(true),
                        child: const Text('Sign out & continue'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (should != true || !mounted) return;
    try {
      await context.read<AuthProvider>().signOut();
    } catch (_) {}
    if (!mounted) return;
    context.go(route);
  }

  void _handleRoleTap(AppRole role) {
    final auth = context.read<AuthProvider>();
    final isAuthed = auth.isAuthenticated;
    final currentRole = auth.userRole;

    String targetRoute;
    switch (role) {
      case AppRole.standardUser:
        targetRoute = AppRoutes.userAuth;
        break;
      case AppRole.merchant:
        targetRoute = AppRoutes.merchantAuth;
        break;
      case AppRole.admin:
        targetRoute = AppRoutes.adminLogin;
        break;
    }

    if (!isAuthed) {
      context.push(targetRoute);
      return;
    }

    // If already signed in, allow continuing in same role, otherwise sign out first.
    if (currentRole == role) {
      if (role == AppRole.merchant) {
        context.go(auth.merchantHasFullAccess ? AppRoutes.merchantDashboard : AppRoutes.merchantOnboarding);
      } else if (role == AppRole.standardUser) {
        context.go(AppRoutes.userHome);
      } else {
        context.go(AppRoutes.adminDashboard);
      }
      return;
    }

    _confirmSignOutAndGo(targetRoute);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.paddingLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              if (auth.isAuthenticated) ...[
                Container(
                  padding: AppSpacing.paddingLg,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    color: cs.surfaceContainerHighest,
                    border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined, color: cs.primary),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Signed in',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Current mode: ${auth.userRole?.displayName ?? 'Unknown'}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await context.read<AuthProvider>().signOut();
                          } catch (_) {}
                          if (!context.mounted) return;
                          context.go(AppRoutes.roleSelection);
                        },
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
              Text(
                l10n.roleSelectionTitle,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.roleSelectionSubtitle,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              RoleOptionCard(
                icon: Icons.person_outline,
                title: l10n.userRole,
                subtitle: l10n.userRoleDesc,
                color: Theme.of(context).colorScheme.primary,
                onTap: () => _handleRoleTap(AppRole.standardUser),
              ),
              const SizedBox(height: AppSpacing.lg),
              RoleOptionCard(
                icon: Icons.store_outlined,
                title: l10n.merchantRole,
                subtitle: l10n.merchantRoleDesc,
                color: Theme.of(context).colorScheme.secondary,
                onTap: () => _handleRoleTap(AppRole.merchant),
              ),
              const SizedBox(height: AppSpacing.lg),
              RoleOptionCard(
                icon: Icons.admin_panel_settings_outlined,
                title: l10n.adminRole,
                subtitle: l10n.adminRoleDesc,
                color: Theme.of(context).colorScheme.tertiary,
                onTap: () => _handleRoleTap(AppRole.admin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoleOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const RoleOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: AppSpacing.paddingLg,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
