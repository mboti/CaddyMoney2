import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:caddymoney/core/config/supabase_config.dart';

class AdminOverviewMetrics {
  final int totalUsers;
  final int totalMerchants;
  final int totalTransactions;
  final double transactionVolume;

  const AdminOverviewMetrics({
    required this.totalUsers,
    required this.totalMerchants,
    required this.totalTransactions,
    required this.transactionVolume,
  });
}

class AdminService {
  Future<AdminOverviewMetrics> fetchOverviewMetrics({int maxVolumeRows = 5000}) async {
    try {
      final supabase = SupabaseConfig.client;

      // Counts (cheap, server-side)
      // NOTE: The repo currently uses a Supabase Dart version that doesn't expose
      // `FetchOptions(head/count)` or `select(..., count:)`. To keep compatibility,
      // we fetch IDs and count client-side.
      final usersRows = await supabase.from('profiles').select('id') as List;
      final merchantsRows = await supabase.from('merchants').select('id') as List;
      final transactionsRows = await supabase.from('transactions').select('id') as List;

      // Volume: sum client-side (keeps schema-independent; you can later replace with an RPC).
      // We sum completed only.
      final volumeRows = await supabase
          .from('transactions')
          .select('amount')
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(maxVolumeRows) as List;

      var volume = 0.0;
      for (final r in volumeRows) {
        if (r is Map && r['amount'] is num) volume += (r['amount'] as num).toDouble();
      }

      return AdminOverviewMetrics(
        totalUsers: usersRows.length,
        totalMerchants: merchantsRows.length,
        totalTransactions: transactionsRows.length,
        transactionVolume: volume,
      );
    } catch (e) {
      debugPrint('AdminService.fetchOverviewMetrics failed: $e');
      rethrow;
    }
  }
}

class FetchOptions {
  const FetchOptions();
}
