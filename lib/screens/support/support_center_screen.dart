import 'package:flutter/material.dart';

import 'package:caddymoney/core/enums/support_requester_type.dart';
import 'package:caddymoney/screens/support/support_inbox_screen.dart';
import 'package:caddymoney/screens/support/support_request_form_screen.dart';
import 'package:caddymoney/services/support_request_service.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';

class SupportCenterArgs {
  final SupportRequesterType requesterType;
  final int initialTabIndex;

  const SupportCenterArgs({required this.requesterType, this.initialTabIndex = 0});
}

class SupportCenterScreen extends StatefulWidget {
  final SupportCenterArgs args;
  const SupportCenterScreen({super.key, required this.args});

  @override
  State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<SupportInboxBodyState> _inboxKey = GlobalKey<SupportInboxBodyState>();
  final _service = SupportRequestService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.args.initialTabIndex.clamp(0, 1));

    // IMPORTANT: Opening the Support Center (even on the "Support request" tab)
    // should acknowledge all admin responses as seen.
    //
    // This ensures the bell red-dot disappears immediately and does not return
    // after navigating back to Home/other menus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.markAllMyAdminResponsesSeen(requesterType: widget.args.requesterType);
    });

    _tabController.addListener(() {
      // Only acknowledge once the user actually opens the inbox tab.
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _inboxKey.currentState?.acknowledgeAllAsSeen();
      }
    });

    // If we land directly on the inbox tab, acknowledge on first frame.
    if (_tabController.index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _inboxKey.currentState?.acknowledgeAllAsSeen());
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onSubmitted() {
    // Switch to Status tab (soft) and refresh list.
    _tabController.animateTo(1, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    _inboxKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CaddyMoneyTopAppBar(showLeading: true),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: AppSpacing.paddingLg.copyWith(bottom: AppSpacing.md),
              child: Container(
                height: 56,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.7)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg - 2),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                    labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    unselectedLabelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    labelColor: cs.onPrimary,
                    unselectedLabelColor: cs.onSurfaceVariant,
                    labelPadding: EdgeInsets.zero,
                    tabs: const [
                      Tab(text: 'request'),
                      Tab(text: 'status'),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const BouncingScrollPhysics(),
                children: [
                  SupportRequestFormPane(requesterType: widget.args.requesterType, autoPopOnSubmit: false, onSubmitted: _onSubmitted),
                  SupportInboxBody(key: _inboxKey, padding: AppSpacing.paddingLg, requesterType: widget.args.requesterType),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
