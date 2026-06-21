import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/models/coupon_model.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class _CouponsListEdgeFunctionNotFound implements Exception {
  final String message;
  const _CouponsListEdgeFunctionNotFound([this.message = 'coupons_list edge function not found']);
  @override
  String toString() => message;
}

class CouponService {
  static String _normCategory(String v) {
    final s = v.trim().toLowerCase();
    if (s.isEmpty) return '';
    // Keep only a-z/0-9 to avoid issues with dashes, spaces, etc.
    final buf = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final isAz = c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122;
      final is09 = c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
      if (isAz || is09) buf.write(c);
    }
    return buf.toString();
  }

  Future<List<CouponModel>> listEligibleCoupons({
    required List<String> merchantCategories,
    String currencyCode = 'EUR',
  }) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return [];

      final categories = merchantCategories.map(_normCategory).where((e) => e.isNotEmpty).toSet();
      if (categories.isEmpty) {
        debugPrint('CouponService.listEligibleCoupons: merchantCategories empty after normalization: $merchantCategories');
        return [];
      }

      // Prefer the Edge Function (works even if RLS policies later change), but
      // fall back to a direct SELECT if the function isn't deployed.
      // If the coupons table is not populated (common during early iterations),
      // fall back again to deriving balances from the transactions ledger.
      List<CouponModel> all;
      try {
        all = await _listMyActiveCouponsViaEdgeFunction(currencyCode: currencyCode);
      } on _CouponsListEdgeFunctionNotFound catch (e) {
        debugPrint('CouponService.listEligibleCoupons: $e; falling back to direct SELECT');
        // IMPORTANT: keep the direct SELECT as permissive as possible.
        // Real-world datasets often contain status/currency with inconsistent casing
        // (e.g. "ACTIVE" / "eur"). Filtering strictly in SQL can make it look like
        // the user has no coupons.
        all = await _listMyCouponsDirect(uid: uid);
      }

      // If the coupons table is empty but the app shows "available amounts by service",
      // it means the category budgets are being tracked via transactions.metadata.category.
      // In that case, synthesize coupon-like objects per category from the ledger.
      if (all.isEmpty) {
        debugPrint('CouponService.listEligibleCoupons: coupons table empty; deriving category balances from transactions.');
        all = await _deriveCouponsFromTransactions(uid: uid, currencyCode: currencyCode);
      }

      // Safety: only active, positive-balance coupons should be usable.
      if (all.isEmpty) {
        debugPrint(
          'CouponService.listEligibleCoupons: 0 coupons returned for user. '
          'If you see amounts on the home screen, note those are based on transaction totals, not the coupons table.',
        );
      }

      all = all
          .where((c) => c.status.toLowerCase() == 'active')
          .where((c) => c.currencyCode.toUpperCase() == currencyCode.toUpperCase())
          .where((c) => c.balance > 0)
          .toList(growable: false);

      final eligible = all.where((c) => categories.contains(_normCategory(c.category))).toList(growable: false);

      if (eligible.isEmpty) {
        debugPrint(
          'CouponService.listEligibleCoupons: 0 eligible. merchantCategories(raw)=$merchantCategories normalized=$categories; '
          'coupons(active)=${all.map((c) => c.category).toList()}',
        );
      }

      return eligible;
    } catch (e) {
      debugPrint('CouponService.listEligibleCoupons failed: $e');
      return [];
    }
  }

  Future<List<CouponModel>> _deriveCouponsFromTransactions({required String uid, required String currencyCode}) async {
    try {
      // We treat the transaction ledger as the source of truth for category budgets.
      // Available balance(category) = sum(credits to me tagged category) - sum(merchant spends by me tagged category)
      // SECURITY: This is ONLY a UI hint; final validation happens server-side.

      final rows = await SupabaseConfig.client
          .from('transactions')
          .select('amount,currency_code,type,status,sender_profile_id,receiver_profile_id,metadata,created_at,updated_at')
          .eq('status', 'completed')
          // We only need rows that involve me.
          .or('sender_profile_id.eq.$uid,receiver_profile_id.eq.$uid')
          .order('created_at', ascending: false)
          .limit(2000);

      if (rows is! List) {
        debugPrint('CouponService._deriveCouponsFromTransactions unexpected response: $rows');
        return [];
      }

      final Map<String, ({String display, double balance, DateTime latest})> byCategory = {};

      for (final r in rows.whereType<Map>()) {
        final m = Map<String, dynamic>.from(r);
        final rowCurrency = (m['currency_code']?.toString() ?? '').toUpperCase();
        if (rowCurrency.isEmpty || rowCurrency != currencyCode.toUpperCase()) continue;

        final metadata = m['metadata'];
        if (metadata is! Map) continue;
        final rawCategory = metadata['category']?.toString();
        if (rawCategory == null || rawCategory.trim().isEmpty) continue;

        final categoryDisplay = rawCategory.trim();
        final categoryKey = _normCategory(categoryDisplay);
        if (categoryKey.isEmpty) continue;

        final type = (m['type']?.toString() ?? '').trim();
        final amount = (m['amount'] as num?)?.toDouble() ?? 0;
        if (amount <= 0) continue;

        final senderId = m['sender_profile_id']?.toString();
        final receiverId = m['receiver_profile_id']?.toString();

        // Credits: any completed flow where I am the receiver (budget top-up)
        // Debits: merchant spend where I am the sender.
        final isCredit = receiverId == uid;
        final isDebit = senderId == uid && type == 'userToMerchant';
        if (!isCredit && !isDebit) continue;

        DateTime latest;
        try {
          latest = DateTime.parse((m['updated_at'] ?? m['created_at']).toString());
        } catch (_) {
          latest = DateTime.now().toUtc();
        }

        final existing = byCategory[categoryKey];
        final signed = isCredit ? amount : -amount;
        if (existing == null) {
          byCategory[categoryKey] = (display: categoryDisplay, balance: signed, latest: latest);
        } else {
          final newLatest = latest.isAfter(existing.latest) ? latest : existing.latest;
          byCategory[categoryKey] = (display: existing.display, balance: existing.balance + signed, latest: newLatest);
        }
      }

      final now = DateTime.now().toUtc();
      final list = byCategory.entries
          .map((e) {
            final key = e.key;
            final v = e.value;
            final bal = v.balance;
            return CouponModel(
              // Special ID scheme understood by PaymentIntentService.
              id: 'category:$key',
              profileId: uid,
              title: v.display,
              category: v.display,
              currencyCode: currencyCode,
              balance: bal,
              status: 'active',
              createdAt: now,
              updatedAt: v.latest,
            );
          })
          .where((c) => c.balance > 0)
          .toList(growable: false);

      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      debugPrint('CouponService._deriveCouponsFromTransactions: derived=${list.length} categories');
      return list;
    } catch (e) {
      debugPrint('CouponService._deriveCouponsFromTransactions failed: $e');
      return [];
    }
  }

  Future<List<CouponModel>> _listMyCouponsDirect({required String uid}) async {
    try {
      final res = await SupabaseConfig.client
          .from('coupons')
          .select('id,profile_id,title,category,currency_code,balance,status,created_at,updated_at')
          .eq('profile_id', uid)
          .order('updated_at', ascending: false);

      if (res is List) {
        final list = res
            .whereType<Map>()
            .map((e) => CouponModel.fromJson(Map<String, dynamic>.from(e)))
            .where((c) => c.id.isNotEmpty)
            .toList(growable: false);

        if (list.isEmpty) {
          debugPrint('CouponService._listMyCouponsDirect: 0 rows for profile_id=$uid (RLS or no data).');
        } else {
          debugPrint(
            'CouponService._listMyCouponsDirect: rows=${list.length} '
            'sample={category:${list.first.category}, status:${list.first.status}, currency:${list.first.currencyCode}, balance:${list.first.balance}}',
          );
        }

        return list;
      }
      debugPrint('CouponService._listMyCouponsDirect unexpected response: $res');
      return [];
    } catch (e) {
      debugPrint('CouponService._listMyCouponsDirect failed: $e');
      return [];
    }
  }

  Future<List<CouponModel>> _listMyActiveCouponsViaEdgeFunction({required String currencyCode}) async {
    try {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session == null) return [];

      final uri = Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/coupons_list');
      final jwt = session.accessToken.trim().replaceAll(RegExp(r'\s+'), '');

      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $jwt',
          'authorization': 'Bearer $jwt',
          'apikey': SupabaseConfig.anonKey,
          'x-client-info': 'caddymoney-flutter',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'currency_code': currencyCode}),
      );

      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = res.body;
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (res.statusCode == 404) {
          throw const _CouponsListEdgeFunctionNotFound();
        }
        final msg = decoded is Map
            ? (decoded['error'] ?? decoded['message'] ?? 'Request failed.').toString()
            : 'Request failed.';
        debugPrint('CouponService.coupons_list failed: status=${res.statusCode} body=$decoded');
        return [];
      }

      if (decoded is Map && decoded['success'] == true && decoded['coupons'] is List) {
        final list = decoded['coupons'] as List;
        return list
            .whereType<Map>()
            .map((e) => CouponModel.fromJson(Map<String, dynamic>.from(e)))
            .where((c) => c.id.isNotEmpty)
            .toList(growable: false);
      }

      debugPrint('CouponService.coupons_list unexpected response: $decoded');
      return [];
    } catch (e) {
      debugPrint('CouponService._listMyActiveCouponsViaEdgeFunction failed: $e');
      return [];
    }
  }
}
