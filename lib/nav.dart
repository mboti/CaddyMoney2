import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:caddymoney/screens/splash_screen.dart';
import 'package:caddymoney/screens/role_selection_screen.dart';
import 'package:caddymoney/screens/auth/user_auth_screen.dart';
import 'package:caddymoney/screens/auth/merchant_auth_screen.dart';
import 'package:caddymoney/screens/auth/admin_login_screen.dart';
import 'package:caddymoney/screens/user/user_home_screen.dart';
import 'package:caddymoney/screens/merchant/merchant_dashboard_screen.dart';
import 'package:caddymoney/screens/merchant/merchant_transactions_screen.dart';
import 'package:caddymoney/screens/merchant/merchant_settings_screen.dart';
import 'package:caddymoney/screens/merchant/merchant_onboarding_kyc_screen.dart';
import 'package:caddymoney/screens/merchant/merchant_under_review_screen.dart';
import 'package:caddymoney/screens/admin/admin_dashboard_screen.dart';
import 'package:caddymoney/screens/admin/admin_merchant_review_screen.dart';
import 'package:caddymoney/screens/admin/admin_manage_merchants_screen.dart';
import 'package:caddymoney/screens/admin/admin_support_requests_screen.dart';
import 'package:caddymoney/screens/admin/admin_support_request_detail_screen.dart';
import 'package:caddymoney/screens/settings_screen.dart';
import 'package:caddymoney/screens/settings/payment_methods_screen.dart';
import 'package:caddymoney/screens/user/receive_money_screen.dart';
import 'package:caddymoney/screens/user/pay_merchant_screen.dart';
import 'package:caddymoney/screens/user/send_money_screen.dart';
import 'package:caddymoney/screens/user/transactions_screen.dart';
import 'package:caddymoney/screens/user/map_screen.dart';
import 'package:caddymoney/screens/user/qr_scan_screen.dart';
import 'package:caddymoney/screens/user/qr_payment_confirmation_screen.dart';
import 'package:caddymoney/screens/support/support_request_form_screen.dart';
import 'package:caddymoney/screens/support/support_inbox_screen.dart';
import 'package:caddymoney/screens/support/support_center_screen.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/core/enums/app_role.dart';
import 'package:caddymoney/core/enums/merchant_status.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';
import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/core/utils/router_refresh.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: _AppRouterRefreshListenable(),
    redirect: (context, state) {
      final auth = context.read<AuthProvider>();
      final location = state.matchedLocation;

      final isMerchant = auth.userRole == AppRole.merchant;
      final isAuthed = auth.isAuthenticated;

      final isPublicRoute = location == AppRoutes.splash ||
          location == AppRoutes.roleSelection ||
          location == AppRoutes.userAuth ||
          location == AppRoutes.merchantAuth ||
          location == AppRoutes.adminLogin;

      // Always allow public routes.
      if (isPublicRoute) return null;

      // Require login for protected areas.
      // (Note: don't use naive startsWith('/merchant') because it matches '/merchant-auth'.)
      final isMerchantProtected = location == AppRoutes.merchantDashboard ||
          location == AppRoutes.merchantTransactions ||
          location == AppRoutes.merchantSettings ||
          location == AppRoutes.merchantOnboarding ||
          location == AppRoutes.merchantUnderReview ||
          location == AppRoutes.supportRequest ||
          location == AppRoutes.supportCenter ||
          location == AppRoutes.supportInbox ||
          location.startsWith('${AppRoutes.supportInbox}/');
      final isUserProtected = location == AppRoutes.userHome ||
          location == AppRoutes.sendMoney ||
          location == AppRoutes.receiveMoney ||
           location == AppRoutes.payMerchant ||
          location == AppRoutes.transactions ||
           location == AppRoutes.userMap ||
          location == AppRoutes.profile ||
          location == AppRoutes.paymentMethods ||
           location == AppRoutes.settings ||
           location == AppRoutes.qrScan ||
            location == AppRoutes.qrPaymentConfirm ||
             location == AppRoutes.supportRequest ||
             location == AppRoutes.supportCenter ||
            location == AppRoutes.supportInbox ||
            location.startsWith('${AppRoutes.supportInbox}/');
      final isAdminProtected = location == AppRoutes.adminDashboard ||
          location == AppRoutes.adminMerchantReview ||
          location == AppRoutes.adminManageMerchants ||
          location == AppRoutes.adminSupportRequests ||
          location.startsWith('${AppRoutes.adminSupportRequests}/');

      if (!isAuthed && (isMerchantProtected || isUserProtected || isAdminProtected)) {
        return AppRoutes.roleSelection;
      }

      // Merchant access restriction: until KYC is complete AND verified.
      if (isMerchant && isAuthed) {
        final merchant = auth.currentMerchant;
        final isPendingReview = merchant?.status == MerchantStatus.pending && merchant?.profileCompleted == true;
        final isOnboarding = location == AppRoutes.merchantOnboarding;
        final isUnderReview = location == AppRoutes.merchantUnderReview;

        // Only gate *merchant protected routes*.
        if (isMerchantProtected) {
          // If KYC was submitted and is pending review, always land on the
          // dedicated confirmation screen after login/restart.
          if (isPendingReview) {
            if (!isUnderReview) return AppRoutes.merchantUnderReview;
            return null;
          }

          if (!auth.merchantHasFullAccess) {
            // Merchants without full access are allowed to reach the onboarding and
            // the under-review confirmation screen.
            if (!isOnboarding && !isUnderReview) return AppRoutes.merchantOnboarding;
          } else {
            if (isOnboarding || isUnderReview) return AppRoutes.merchantDashboard;
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SplashScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.roleSelection,
        name: 'role-selection',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: RoleSelectionScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.userAuth,
        name: 'user-auth',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: UserAuthScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.merchantAuth,
        name: 'merchant-auth',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MerchantAuthScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminLogin,
        name: 'admin-login',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: AdminLoginScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.userHome,
        name: 'user-home',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: UserHomeScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.merchantDashboard,
        name: 'merchant-dashboard',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MerchantDashboardScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.merchantTransactions,
        name: 'merchant-transactions',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MerchantTransactionsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.merchantSettings,
        name: 'merchant-settings',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MerchantSettingsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.merchantOnboarding,
        name: 'merchant-onboarding',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MerchantOnboardingKycScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.merchantUnderReview,
        name: 'merchant-under-review',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MerchantUnderReviewScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminDashboard,
        name: 'admin-dashboard',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: AdminDashboardScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminMerchantReview,
        name: 'admin-merchant-review',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is AdminMerchantReviewArgs) {
            return NoTransitionPage(child: AdminMerchantReviewScreen(args: extra));
          }
          // Fallback if route was opened incorrectly.
          return const NoTransitionPage(child: AdminDashboardScreen());
        },
      ),
      GoRoute(
        path: AppRoutes.adminManageMerchants,
        name: 'admin-manage-merchants',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: AdminManageMerchantsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminSupportRequests,
        name: 'admin-support-requests',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: AdminSupportRequestsScreen(),
        ),
        routes: [
          GoRoute(
            path: ':id',
            name: 'admin-support-request-detail',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || id.trim().isEmpty) {
                return const NoTransitionPage(child: AdminSupportRequestsScreen());
              }
              return NoTransitionPage(child: AdminSupportRequestDetailScreen(requestId: id));
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SettingsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.supportRequest,
        name: 'support-request',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is SupportRequestFormArgs) {
            // Keep the legacy route name/path, but show the modern 2-tab Support Center
            // (request/status) so users can track admin responses.
            return NoTransitionPage(
              child: SupportCenterScreen(
                args: SupportCenterArgs(requesterType: extra.requesterType, initialTabIndex: 0),
              ),
            );
          }
          return const NoTransitionPage(child: SettingsScreen());
        },
      ),
      GoRoute(
        path: AppRoutes.supportCenter,
        name: 'support-center',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is SupportCenterArgs) {
            return NoTransitionPage(child: SupportCenterScreen(args: extra));
          }
          return const NoTransitionPage(child: SettingsScreen());
        },
      ),
      GoRoute(
        path: AppRoutes.supportInbox,
        name: 'support-inbox',
        pageBuilder: (context, state) {
          final extra = state.extra;
          SupportRequesterType? requesterType;
          if (extra is SupportRequesterType) requesterType = extra;
          if (extra is SupportCenterArgs) requesterType = extra.requesterType;
          return NoTransitionPage(child: SupportInboxScreen(requesterType: requesterType));
        },
        routes: [
          GoRoute(
            path: ':id',
            name: 'support-inbox-detail',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || id.trim().isEmpty) {
                final extra = state.extra;
                SupportRequesterType? requesterType;
                if (extra is SupportRequesterType) requesterType = extra;
                if (extra is SupportCenterArgs) requesterType = extra.requesterType;
                return NoTransitionPage(child: SupportInboxScreen(requesterType: requesterType));
              }
              return NoTransitionPage(child: SupportInboxDetailScreen(requestId: id));
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.paymentMethods,
        name: 'payment-methods',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: PaymentMethodsScreen(),
        ),
      ),

      // User flows
      GoRoute(
        path: AppRoutes.sendMoney,
        name: 'send-money',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SendMoneyScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.receiveMoney,
        name: 'receive-money',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ReceiveMoneyScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.payMerchant,
        name: 'pay-merchant',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: PayMerchantScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.qrScan,
        name: 'qr-scan',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: QrScanScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.qrPaymentConfirm,
        name: 'qr-payment-confirm',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is QrPaymentConfirmArgs) {
            return NoTransitionPage(child: QrPaymentConfirmationScreen(tokenOrId: extra.tokenOrId));
          }
          return const NoTransitionPage(child: QrScanScreen());
        },
      ),
      GoRoute(
        path: AppRoutes.transactions,
        name: 'transactions',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: TransactionsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.userMap,
        name: 'user-map',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: MapScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        name: 'profile',
        pageBuilder: (context, state) => const NoTransitionPage(
          // Backward-compat route: profile is now integrated into Settings.
          child: SettingsScreen(),
        ),
      ),
    ],
  );
}

class AppRoutes {
  static const String splash = '/';
  static const String roleSelection = '/role-selection';
  static const String userAuth = '/user-auth';
  static const String merchantAuth = '/merchant-auth';
  static const String adminLogin = '/admin-login';
  static const String userHome = '/user-home';
  static const String merchantDashboard = '/merchant-dashboard';
  static const String merchantTransactions = '/merchant-transactions';
  static const String merchantSettings = '/merchant-settings';
  static const String merchantOnboarding = '/merchant-onboarding';
  static const String merchantUnderReview = '/merchant-under-review';
  static const String adminDashboard = '/admin-dashboard';
  static const String adminMerchantReview = '/admin-merchant-review';
  static const String adminManageMerchants = '/admin-manage-merchants';
  static const String adminSupportRequests = '/admin-support-requests';
  static const String settings = '/settings';
  static const String supportRequest = '/support-request';
  static const String supportCenter = '/support-center';
  static const String supportInbox = '/support-inbox';
  static const String paymentMethods = '/payment-methods';
  static const String sendMoney = '/send-money';
  static const String receiveMoney = '/receive-money';
  static const String payMerchant = '/pay-merchant';
  static const String qrScan = '/qr-scan';
  static const String qrPaymentConfirm = '/qr-payment-confirm';
  static const String transactions = '/transactions';
  static const String userMap = '/user-map';
  static const String profile = '/profile';
}

class QrPaymentConfirmArgs {
  final String tokenOrId;

  const QrPaymentConfirmArgs({required this.tokenOrId});
}

class _AppRouterRefreshListenable extends ChangeNotifier {
  _AppRouterRefreshListenable() {
    _authSub = SupabaseConfig.client.auth.onAuthStateChange.listen((_) => notifyListeners());
    RouterRefresh.instance.addListener(_onRouterRefresh);
  }

  late final StreamSubscription _authSub;

  void _onRouterRefresh() => notifyListeners();

  @override
  void dispose() {
    _authSub.cancel();
    RouterRefresh.instance.removeListener(_onRouterRefresh);
    super.dispose();
  }
}
