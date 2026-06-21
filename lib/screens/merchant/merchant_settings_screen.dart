import 'package:flutter/material.dart';

import 'package:caddymoney/screens/merchant/widgets/merchant_bottom_nav_bar.dart';
import 'package:caddymoney/screens/settings_screen.dart';

class MerchantSettingsScreen extends StatelessWidget {
  const MerchantSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScreen(
      showAppBarLeading: false,
      bottomNavigationBarOverride: MerchantBottomNavBar(),
    );
  }
}
