import 'package:flutter/foundation.dart';
import 'package:caddymoney/models/wallet_model.dart';
import 'package:caddymoney/core/config/supabase_config.dart';

class WalletService {
  Future<WalletModel?> getMyUserWallet() async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return null;

      final row = await SupabaseService.selectSingle(
        'wallets',
        filters: {'owner_type': 'user', 'profile_id': uid, 'is_active': true},
      );
      if (row == null) return null;
      return WalletModel.fromJson(row);
    } catch (e) {
      debugPrint('WalletService.getMyUserWallet failed: $e');
      return null;
    }
  }

  Future<WalletModel?> getMerchantWallet({required String merchantId}) async {
    try {
      final row = await SupabaseService.selectSingle(
        'wallets',
        filters: {'owner_type': 'merchant', 'merchant_id': merchantId, 'is_active': true},
      );
      if (row == null) return null;
      return WalletModel.fromJson(row);
    } catch (e) {
      debugPrint('WalletService.getMerchantWallet failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> claimTestTopUp({double amount = 1000}) async {
    try {
      final res = await SupabaseConfig.client.rpc('claim_test_topup', params: {'topup_amount': amount});
      if (res is Map<String, dynamic>) return res;
      if (res is Map) return Map<String, dynamic>.from(res);
      return {'success': false, 'error': 'Unexpected response'};
    } catch (e) {
      debugPrint('WalletService.claimTestTopUp failed: $e');
      return {'success': false, 'error': 'Top up failed'};
    }
  }
}
